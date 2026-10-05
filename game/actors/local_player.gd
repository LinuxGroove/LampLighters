class_name LocalPlayer
extends CharacterBody3D
## The villager this device controls: movement, the personal lantern light,
## and choosing what the action buttons do from what's nearby.
##
## Movement happens here for responsiveness and is reported to the host,
## which clamps it. Everything else (relighting, chores, snuffing, taking,
## reporting) is a request the host may refuse.

const SEND_RATE := 15.0
const STEP_SOUNDS := [
	"res://assets/kenney/audio/sfx/footstep_grass_000.ogg",
	"res://assets/kenney/audio/sfx/footstep_grass_001.ogg",
	"res://assets/kenney/audio/sfx/footstep_grass_002.ogg",
	"res://assets/kenney/audio/sfx/footstep_grass_003.ogg",
]

var game: Game
var avatar: Avatar
var light: OmniLight3D
var ghost := false
## What the interact button (A) does here: {kind, target, text}
var interact := {}
## What the special button (X) does here: {kind, target, text, cd}
var special := {}
var can_ring := false
## The action in progress: {kind: "relight"|"chore", target, t}
var busy := {}
var locked := false
var snuff_cd := 0.0
var take_cd := 0.0
var bell_cd := 0.0

var _yaw := 0.0
var _anim := Rules.Anim.IDLE
var _send_t := 0.0
var _step_t := 0.0
var _last_sent := []


func setup(p_game: Game, pos: Vector3) -> void:
	game = p_game
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.4
	cs.shape = cap
	cs.position.y = 0.7
	add_child(cs)
	avatar = Avatar.new()
	avatar.actor_id = game.my_id
	add_child(avatar)
	avatar.setup(game.player_name(game.my_id), int(game.roster.get(game.my_id, {}).get("look", 0)), true)
	light = OmniLight3D.new()
	light.position = Vector3(0.3, 2.2, 0.2)
	light.omni_range = Rules.PERSONAL_LIGHT + 1.8
	light.omni_attenuation = 1.4
	light.light_energy = 1.7
	light.light_color = Color(1.0, 0.74, 0.42)
	light.shadow_enabled = false
	add_child(light)
	global_position = pos
	game.private_changed.connect(_on_private_changed)
	_on_private_changed()


func set_ghost(on: bool) -> void:
	ghost = on
	avatar.set_ghost(on)
	collision_mask = 0 if on else 1
	light.light_color = Color(0.55, 0.75, 1.0) if on else Color(1.0, 0.74, 0.42)
	light.omni_range = Rules.VIEW_RADIUS if on else Rules.PERSONAL_LIGHT + 1.8
	light.light_energy = 0.9 if on else 1.7
	cancel_everything()


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	var center: Vector3 = game.camera.focus
	var to := center - pos
	if to.length() > 0.1:
		_yaw = atan2(to.x, to.z)
		avatar.rotation.y = _yaw


func cancel_everything() -> void:
	if not busy.is_empty():
		busy = {}
		game.hud.close_chore()


func on_denied() -> void:
	if not busy.is_empty():
		busy = {}
		game.hud.close_chore()


func _on_private_changed() -> void:
	var y: Dictionary = game.you
	snuff_cd = float(y.get("snuff_cd", 0.0))
	take_cd = float(y.get("take_cd", 0.0))
	bell_cd = float(y.get("bell_cd", 0.0))
	if y.get("ghost", false) and not ghost:
		set_ghost(true)


func _can_move() -> bool:
	return game.phase == Rules.Phase.NIGHT and not locked and busy.is_empty()


func _physics_process(delta: float) -> void:
	var moving := false
	if _can_move():
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var speed := Rules.GHOST_SPEED if ghost else Rules.WALK_SPEED
		velocity = Vector3(input.x, 0.0, input.y) * speed
		if input.length() > 0.1:
			_yaw = atan2(input.x, input.y)
			moving = true
		move_and_slide()
		var p := global_position
		p.y = 0.0
		global_position = game.village.clamp_to_bounds(p)
	else:
		velocity = Vector3.ZERO
	avatar.rotation.y = lerp_angle(avatar.rotation.y, _yaw, 1.0 - exp(-16.0 * delta))
	var carrying := str(game.you.get("carry", "")) != ""
	if not busy.is_empty():
		_anim = Rules.Anim.INTERACT
	elif moving:
		_anim = Rules.Anim.CARRY_WALK if carrying else Rules.Anim.WALK
	elif _anim != Rules.Anim.EMOTE_YES and _anim != Rules.Anim.EMOTE_NO:
		_anim = Rules.Anim.CARRY_IDLE if carrying else Rules.Anim.IDLE
	avatar.set_anim(_anim)
	if moving and not ghost:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.36
			LGAudio.play_sfx(STEP_SOUNDS[randi() % STEP_SOUNDS.size()], -16.0, 0.1)
	_send_t += delta
	if _send_t >= 1.0 / SEND_RATE and game.phase == Rules.Phase.NIGHT:
		_send_t = 0.0
		var state := [snappedf(global_position.x, 0.01), snappedf(global_position.z, 0.01), snappedf(_yaw, 0.02), _anim]
		if state != _last_sent:
			_last_sent = state
			game.to_host("_c_state", [Vector3(state[0], 0.0, state[1]), state[2], state[3]])


func _process(delta: float) -> void:
	if game.phase == Rules.Phase.NIGHT:
		snuff_cd = maxf(0.0, snuff_cd - delta)
		take_cd = maxf(0.0, take_cd - delta)
		bell_cd = maxf(0.0, bell_cd - delta)
	_update_targets()
	if busy.get("kind", "") == "relight":
		busy.t += delta
		if not Input.is_action_pressed("interact"):
			game.act(Rules.Act.CANCEL)
			busy = {}
		elif busy.t >= Rules.RELIGHT_TIME:
			game.act(Rules.Act.RELIGHT_DONE, busy.target)
			busy = {}


func relight_progress() -> float:
	return busy.t / Rules.RELIGHT_TIME if busy.get("kind", "") == "relight" else -1.0


func _update_targets() -> void:
	interact = {}
	special = {}
	can_ring = false
	if game.phase != Rules.Phase.NIGHT:
		return
	var pos := global_position
	var alive: bool = game.is_alive()
	if alive:
		for rid in game.visible_remains:
			var r: Dictionary = game.visible_remains[rid]
			if _flat(pos, r.pos) <= Rules.INTERACT_RANGE:
				interact = {"kind": "report", "target": rid, "text": "Report %s's lantern" % game.player_name(r.victim)}
				break
	if interact.is_empty() and alive:
		var i := _nearest_lantern(false, Rules.INTERACT_RANGE)
		if i >= 0:
			interact = {"kind": "relight", "target": i, "text": "Hold to relight the lantern"}
	if interact.is_empty():
		var best := Rules.INTERACT_RANGE
		for c in game.available_chores():
			var sp: Vector3 = game.station_position(c.data.station)
			var d := _flat(pos, sp)
			if d <= best:
				best = d
				var label: String = Rules.CHORES[c.key].label
				if c.steps > 1:
					label += " (%d/%d)" % [c.step + 1, c.steps]
				if not c.data.get("dark", false) and not game.work_lit(sp):
					interact = {"kind": "dark", "target": c.index, "text": "Too dark to work. Relight a lantern nearby"}
				else:
					interact = {"kind": "chore", "target": c.index, "text": label, "chore": c}
	if alive and game.you.get("bell_left", 0) > 0 and _flat(pos, game.village.bell_position()) <= Rules.BELL_RANGE:
		can_ring = true
	match game.role:
		Rules.Role.HOLLOW:
			if alive:
				var victim := _nearest_victim()
				if victim != 0:
					special = {"kind": "take", "target": victim, "text": "Take %s" % game.player_name(victim), "cd": take_cd}
				else:
					var i := _nearest_lantern(true, Rules.INTERACT_RANGE)
					if i >= 0:
						special = {"kind": "snuff", "target": i, "text": "Snuff the lantern", "cd": snuff_cd}
		Rules.Role.SEER:
			if alive and not game.you.get("seer_used", false):
				var t := _nearest_view(Rules.SEER_RANGE, false)
				if t != 0:
					special = {"kind": "seer", "target": t, "text": "Look closely at %s" % game.player_name(t), "cd": 0.0}
	if ghost and game.role != Rules.Role.HOLLOW and not game.you.get("flicker_used", false):
		var i := _nearest_lantern(true, Rules.INTERACT_RANGE + 1.5)
		if i >= 0:
			special = {"kind": "flicker", "target": i, "text": "Flicker the lantern", "cd": 0.0}


func _unhandled_input(event: InputEvent) -> void:
	if game.phase != Rules.Phase.NIGHT or locked:
		return
	if event.is_action_pressed("interact") and busy.is_empty() and not interact.is_empty():
		get_viewport().set_input_as_handled()
		_do_interact()
	elif event.is_action_pressed("special") and busy.is_empty() and not special.is_empty():
		get_viewport().set_input_as_handled()
		_do_special()
	elif event.is_action_pressed("ring_bell") and busy.is_empty() and can_ring:
		get_viewport().set_input_as_handled()
		if bell_cd > 0.0:
			game.toast.emit("The bell is still ringing out.")
		else:
			game.act(Rules.Act.BELL)
	else:
		for n in range(1, 5):
			if event.is_action_pressed("emote_%d" % n):
				get_viewport().set_input_as_handled()
				game.to_host("_c_emote", [n])
				if n == 3:
					_anim = Rules.Anim.EMOTE_YES
				elif n == 4:
					_anim = Rules.Anim.EMOTE_NO
				get_tree().create_timer(1.2).timeout.connect(func():
					if _anim in [Rules.Anim.EMOTE_YES, Rules.Anim.EMOTE_NO]:
						_anim = Rules.Anim.IDLE)
				return


func _do_interact() -> void:
	match interact.kind:
		"dark":
			game.toast.emit("Your lantern is too dim to work by. Relight a lantern nearby.")
		"report":
			game.act(Rules.Act.REPORT, interact.target)
		"relight":
			busy = {"kind": "relight", "target": interact.target, "t": 0.0}
			game.act(Rules.Act.RELIGHT_START, interact.target)
		"chore":
			var idx: int = interact.target
			busy = {"kind": "chore", "target": idx, "t": 0.0}
			game.act(Rules.Act.CHORE_START, idx)
			game.hud.open_chore(interact.chore, func(done: bool):
				if busy.get("kind", "") != "chore":
					return
				busy = {}
				game.act(Rules.Act.CHORE_DONE if done else Rules.Act.CANCEL, idx if done else 0))


func _do_special() -> void:
	if float(special.get("cd", 0.0)) > 0.0:
		game.toast.emit("Not yet. Wait %d s." % ceili(special.cd))
		return
	match special.kind:
		"take":
			game.act(Rules.Act.TAKE, special.target)
		"snuff":
			game.act(Rules.Act.SNUFF, special.target)
		"seer":
			game.act(Rules.Act.SEER, special.target)
		"flicker":
			game.act(Rules.Act.FLICKER, special.target)


func _nearest_lantern(want_lit: bool, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in game.lit.size():
		if game.lit[i] != want_lit:
			continue
		var d := _flat(global_position, game.lantern_position(i))
		if d <= best_d:
			best = i
			best_d = d
	return best


func _nearest_victim() -> int:
	if game.lit_at(global_position):
		return 0
	var best := 0
	var best_d := Rules.TAKE_RANGE
	for v in game.visible_views():
		if v.ghost or v.ally:
			continue
		var d := _flat(global_position, v.global_position)
		if d <= best_d and not game.lit_at(v.global_position):
			best = v.actor_id
			best_d = d
	return best


func _nearest_view(reach: float, allow_ghosts: bool) -> int:
	var best := 0
	var best_d := reach
	for v in game.visible_views():
		if v.ghost and not allow_ghosts:
			continue
		var d := _flat(global_position, v.global_position)
		if d <= best_d:
			best = v.actor_id
			best_d = d
	return best


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
