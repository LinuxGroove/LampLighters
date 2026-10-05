extends Node
## Local LLM "brains" for AI players, through Lemonade Server (autoload: LGBrain).
##
## Modes (setting ai/mode):
##   off       never use a model; games fall back to their scripted AI
##   auto      the embedded Lemonade bundled with the game if present,
##             otherwise a Lemonade (or other OpenAI-compatible) server
##             already running at ai/external_url, otherwise off
##   embedded  start the bundled `lemond` privately on localhost
##   external  use ai/external_url only
##
## The embedded server is started only when a game asks for it, with a random
## port and API key known only to this process, and is stopped on exit.
## Models download on first use into a folder that survives snap refreshes
## ($SNAP_USER_COMMON), so they are not copied on every update.

signal state_changed(state: String, detail: String)

const READY_TIMEOUT := 60.0

var state := "off"
var detail := ""
var progress := 0.0
var model := ""
var source := ""

var _client: LlmClient
var _pid := -1
var _starting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_client = LlmClient.new()
	add_child(_client)


func is_ready() -> bool:
	return state == "ready"


## Path to the bundled lemond binary, or "" if this build has none.
func embedded_binary() -> String:
	var candidates: Array[String] = []
	var settings := get_node_or_null("/root/LGSettings")
	if settings and str(settings.get_value("ai", "lemond_path", "")) != "":
		candidates.append(str(settings.get_value("ai", "lemond_path", "")))
	var snap := OS.get_environment("SNAP")
	if snap != "":
		candidates.append(snap.path_join("lemonade/lemond"))
	candidates.append(OS.get_executable_path().get_base_dir().path_join("lemonade/lemond"))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


## Starts (or connects to) a model server and makes sure the model is loaded.
## Safe to call repeatedly; returns true once ready.
func ensure_ready_async() -> bool:
	if state == "ready":
		return true
	if _starting:
		while _starting:
			await get_tree().create_timer(0.25).timeout
		return state == "ready"
	_starting = true
	var ok := await _start()
	_starting = false
	return ok


## Asks the model for a reply. `messages` is OpenAI chat format.
func chat_async(messages: Array, max_tokens := 160, temperature := 0.8, json_mode := false) -> String:
	if state != "ready":
		return ""
	return await _client.chat(model, messages, max_tokens, temperature, json_mode)


func stop() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1
	if state != "off":
		_set_state("off", "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _pid > 0:
			OS.kill(_pid)
			_pid = -1


func _start() -> bool:
	var settings := get_node("/root/LGSettings")
	var mode := str(settings.get_value("ai", "mode"))
	model = str(settings.get_value("ai", "model"))
	if mode == "off":
		_set_state("off", "AI brains are turned off")
		return false
	var binary := embedded_binary() if mode in ["auto", "embedded"] else ""
	if binary != "":
		if not await _start_embedded(binary):
			return false
	elif mode in ["auto", "external"]:
		_client.base_url = str(settings.get_value("ai", "external_url")).trim_suffix("/")
		_client.api_key = str(settings.get_value("ai", "external_key", ""))
		source = "external"
		_set_state("starting", "Looking for Lemonade at %s" % _client.base_url)
		var health := await _client.get_json("/health", 3.0)
		if not health.ok:
			_set_state("unavailable", "No local AI server found")
			return false
	else:
		_set_state("unavailable", "This build has no embedded Lemonade")
		return false
	if not await _ensure_model():
		return false
	_set_state("ready", "%s via %s Lemonade" % [model, source])
	return true


func _start_embedded(binary: String) -> bool:
	source = "embedded"
	var base := OS.get_environment("SNAP_USER_COMMON")
	if base == "":
		base = OS.get_user_data_dir()
	var cache_dir := base.path_join("lemonade/cache")
	var config_dir := base.path_join("lemonade/config")
	DirAccess.make_dir_recursive_absolute(cache_dir)
	DirAccess.make_dir_recursive_absolute(config_dir)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var port := rng.randi_range(20000, 29999)
	var key := ""
	for i in 32:
		key += "%x" % rng.randi_range(0, 15)
	# The child inherits the environment, which is how lemond reads its key.
	OS.set_environment("LEMONADE_API_KEY", key)
	_pid = OS.create_process(binary, [
		"--host", "127.0.0.1", "--port", str(port), "--no-broadcast", cache_dir, config_dir])
	OS.unset_environment("LEMONADE_API_KEY")
	if _pid <= 0:
		_set_state("error", "Could not start the embedded Lemonade server")
		return false
	_client.base_url = "http://127.0.0.1:%d/api/v1" % port
	_client.api_key = key
	_set_state("starting", "Starting the local AI server")
	var waited := 0.0
	while waited < READY_TIMEOUT:
		if not OS.is_process_running(_pid):
			_pid = -1
			_set_state("error", "The local AI server stopped unexpectedly")
			return false
		var health := await _client.get_json("/health", 2.0)
		if health.ok:
			return true
		await get_tree().create_timer(0.5).timeout
		waited += 0.5 + 0.1
	_set_state("error", "The local AI server did not start in time")
	stop()
	return false


func _ensure_model() -> bool:
	var models := await _client.get_json("/models", 10.0)
	var downloaded := false
	if models.ok and typeof(models.data) == TYPE_DICTIONARY:
		for m in models.data.get("data", []):
			if str(m.get("id", "")) == model:
				downloaded = bool(m.get("downloaded", true))
	if not downloaded:
		if not await _pull_model():
			return false
	_set_state("loading", "Loading %s" % model)
	var load_res := await _client.post_json("/load", {"model_name": model, "ctx_size": 4096}, 300.0)
	if not load_res.ok and load_res.code != 404:
		_set_state("error", "Could not load %s: %s" % [model, load_res.error])
		return false
	return true


func _pull_model() -> bool:
	_set_state("downloading", "Downloading %s" % model)
	var start := await _client.post_json("/pull", {"model_name": model, "stream": true, "subscribe": false}, 30.0)
	if start.code == 404:
		return true  # Not Lemonade (plain OpenAI server): assume the model exists.
	if not start.ok:
		_set_state("error", "Could not download %s: %s" % [model, start.error])
		return false
	var missing_for := 0
	while missing_for < 30:
		await get_tree().create_timer(1.0).timeout
		var jobs := await _client.get_json("/downloads", 10.0)
		if not jobs.ok or typeof(jobs.data) != TYPE_ARRAY:
			missing_for += 1
			continue
		var found := false
		for job in jobs.data:
			if str(job.get("model_name", "")) == model:
				found = true
		missing_for = 0 if found else missing_for + 1
		for job in jobs.data:
			if str(job.get("model_name", "")) != model:
				continue
			progress = float(job.get("percent", 0)) / 100.0
			var status := str(job.get("status", ""))
			if bool(job.get("complete", false)) or status == "completed":
				progress = 1.0
				return true
			if status in ["error", "cancelled"]:
				_set_state("error", "Download failed: %s" % str(job.get("error", status)))
				return false
			_set_state("downloading", "Downloading %s (%d%%)" % [model, int(progress * 100.0)])
	# The job finished and was cleared before we saw it complete; check the list.
	var models := await _client.get_json("/models", 10.0)
	if models.ok and typeof(models.data) == TYPE_DICTIONARY:
		for m in models.data.get("data", []):
			if str(m.get("id", "")) == model:
				return true
	_set_state("error", "Download of %s did not finish" % model)
	return false


func _set_state(s: String, d: String) -> void:
	state = s
	detail = d
	state_changed.emit(s, d)
