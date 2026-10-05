class_name Game
extends Node3D
## One night in the village: the map, everyone's avatars, the HUD, and every
## match message between the host and the players.
##
## The same scene runs on every device. On the host it also owns a MatchHost,
## which decides everything; elsewhere it only shows what the host sends. All
## match RPCs live on this node (/root/Game) so their paths match everywhere.

signal intro_received
signal private_changed
signal lanterns_changed
signal status_changed
signal meeting_started(info: Dictionary)
signal meeting_phase_changed(phase: int, seconds: float)
signal meeting_said(id: int, text: String)
signal meeting_voted(id: int)
signal meeting_result(res: Dictionary)
signal meeting_ended
signal game_over(res: Dictionary)
signal toast(text: String)

const QUICK_CHAT := [
	"I suspect {a}.",
	"I trust {a}.",
	"I was near {place}.",
	"I saw {a} near {place}.",
	"Let's skip. We don't know enough.",
	"It wasn't me!",
	"Where was everyone?",
]
const EMOTES := {
	1: "res://assets/kenney/emotes/emote_exclamation.png",
	2: "res://assets/kenney/emotes/emote_question.png",
	3: "res://assets/kenney/emotes/emote_faceHappy.png",
	4: "res://assets/kenney/emotes/emote_anger.png",
}
const MUSIC_NIGHT := "res://assets/kenney/audio/music/sad_town.ogg"
const MUSIC_MEETING := "res://assets/kenney/audio/music/mischief_stroll.ogg"
const SFX_BELL := "res://assets/kenney/audio/sfx/impactBell_heavy_000.ogg"
const SFX_SNUFF := "res://assets/kenney/audio/sfx/cloth1.ogg"
const SFX_RELIGHT := "res://assets/kenney/audio/sfx/metalLatch.ogg"
const SFX_TAKEN := "res://assets/kenney/audio/sfx/impactSoft_heavy_000.ogg"
const SFX_DENIED := "res://assets/kenney/audio/sfx/error_001.ogg"

## Set by Session before the scene enters the tree.
var config := {}
var my_id := 1
var village: Village
var host: MatchHost
var player: LocalPlayer
var camera: FollowCamera
var hud: Hud

# What this device knows about the match
var roster := {}
var role := -1
var allies: Array = []
var you := {}
var lit: Array[bool] = []
var night_left := 0.0
var night_total := 1.0
var chores_done := 0
var chores_total := 0
var phase := Rules.Phase.LOADING
var meeting := {}
var result := {}
var visible_remains := {}  # remains id -> {victim, pos}
var landmarks: Array[String] = []
var settings := {}

var _lantern_nodes: Array = []
var _views := {}  # id -> Avatar
var _remain_nodes := {}
var _actors_root: Node3D
var _prints: MultiMeshInstance3D


func _ready() -> void:
	my_id = multiplayer.get_unique_id()
	settings = Rules.DEFAULT_SETTINGS.duplicate()
	settings.merge(config.get("settings", {}), true)
	for id in config.get("players", {}):
		var p: Dictionary = config.players[id]
		roster[id] = {"name": p.name, "look": p.look}
	village = (load(config.get("map", "res://game/world/moonpatch_village.tscn")) as PackedScene).instantiate()
	add_child(village)
	_lantern_nodes = village.lanterns()
	for l in _lantern_nodes:
		lit.append(true)
	landmarks = village.landmark_names()
	_actors_root = Node3D.new()
	_actors_root.name = "Actors"
	add_child(_actors_root)
	_prints = _make_prints()
	add_child(_prints)
	camera = FollowCamera.new()
	add_child(camera)
	camera.snap_to(village.bell_position())
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	if Session.is_host():
		host = MatchHost.new()
		host.name = "Host"
		add_child(host)
		host.setup(config, self, village)
		host.ended.connect(Session.report_round)
	Session.left.connect(_on_session_left)
	LGAudio.play_music(MUSIC_NIGHT, -4.0)
	Session.report_loaded()


func on_player_left(id: int) -> void:
	if host:
		host.on_player_left(id)


func _on_session_left(reason: String) -> void:
	LGScenes.change_scene("res://game/ui/title.tscn", func(node): node.set("message", reason))


# --- Helpers used by the HUD and the local player -----------------------

func player_name(id: int) -> String:
	return str(roster.get(id, {}).get("name", "?"))


func player_color(id: int) -> Color:
	return GameConfig.look_color(int(roster.get(id, {}).get("look", 0)))


func lantern_position(i: int) -> Vector3:
	return (_lantern_nodes[i] as Node3D).global_position


func lit_at(pos: Vector3) -> bool:
	for i in lit.size():
		if lit[i] and Vector2(pos.x, pos.z).distance_to(Vector2(lantern_position(i).x, lantern_position(i).z)) <= Rules.LANTERN_RADIUS:
			return true
	return false


func work_lit(pos: Vector3) -> bool:
	for i in lit.size():
		var lp := lantern_position(i)
		if lit[i] and Vector2(pos.x - lp.x, pos.z - lp.z).length() <= Rules.WORK_LIGHT_RADIUS:
			return true
	return false


func is_ghost() -> bool:
	return bool(you.get("ghost", false))


func is_alive() -> bool:
	return bool(you.get("alive", true))


func view_of(id: int) -> Avatar:
	return _views.get(id)


## Avatars currently visible to this player.
func visible_views() -> Array:
	return _views.values().filter(func(v): return v.shown)


func current_chore() -> Dictionary:
	var chores: Array = you.get("chores", [])
	for i in chores.size():
		var c: Array = chores[i]
		if not c[2]:
			var steps: Array = Rules.CHORES[c[0]].steps
			return {"index": i, "key": c[0], "step": c[1], "data": steps[c[1]], "steps": steps.size()}
	return {}


## Chore steps this player can do right now at any station.
func available_chores() -> Array:
	var out := []
	var chores: Array = you.get("chores", [])
	for i in chores.size():
		var c: Array = chores[i]
		if not c[2]:
			var steps: Array = Rules.CHORES[c[0]].steps
			out.append({"index": i, "key": c[0], "step": c[1], "data": steps[c[1]], "steps": steps.size()})
	return out


func station_position(station_id: String) -> Vector3:
	var s := village.stations()
	return (s[station_id] as Node3D).global_position if s.has(station_id) else Vector3.INF


func quick_chat_text(kind: int, a: int, place: int) -> String:
	if kind < 0 or kind >= QUICK_CHAT.size():
		return ""
	var text: String = QUICK_CHAT[kind]
	text = text.replace("{a}", player_name(a))
	if place >= 0 and place < landmarks.size():
		text = text.replace("{place}", landmarks[place])
	return text


# --- Sending --------------------------------------------------------------

## Host: sends a match message to one player. Calls locally for the host's
## own player and skips bots and players who haven't loaded the village.
func send(peer: int, method: String, args: Array) -> void:
	if peer <= 0:
		return
	if peer == my_id:
		callv(method, args)
		return
	if not Session.loaded_peers.has(peer) or not peer in multiplayer.get_peers():
		return
	var call_args := [peer, method]
	call_args.append_array(args)
	callv("rpc_id", call_args)


func broadcast(method: String, args: Array) -> void:
	if host == null:
		return
	for id in host.actors:
		if id > 0 and not host.actors[id].out:
			send(id, method, args)


func to_host(method: String, args: Array) -> void:
	if Session.is_host():
		callv(method, args)
	else:
		var call_args := [1, method]
		call_args.append_array(args)
		callv("rpc_id", call_args)


func act(kind: int, target := 0) -> void:
	to_host("_c_act", [kind, target])


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return my_id if s == 0 else s


# --- Player -> host -------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _c_state(pos: Vector3, yaw: float, anim: int) -> void:
	if host:
		host.on_state(_sender(), pos, yaw, anim)


@rpc("any_peer", "call_remote", "reliable")
func _c_act(kind: int, target: int) -> void:
	if host:
		host.act(_sender(), kind, target)


@rpc("any_peer", "call_remote", "reliable")
func _c_vote(target: int) -> void:
	if host:
		host.vote(_sender(), target)


@rpc("any_peer", "call_remote", "reliable")
func _c_say(kind: int, a: int, place: int) -> void:
	if host:
		var text := quick_chat_text(kind, a, place)
		if text != "":
			host.say(_sender(), text)


@rpc("any_peer", "call_remote", "reliable")
func _c_emote(n: int) -> void:
	if host:
		host.emote(_sender(), n)


# --- Host -> player -------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _h_intro(info: Dictionary) -> void:
	role = info.role
	allies = info.allies
	roster = info.roster
	settings = info.settings
	night_left = info.night
	night_total = maxf(info.night, 1.0)
	you = info.you
	phase = Rules.Phase.NIGHT
	player = LocalPlayer.new()
	player.name = "Me"
	_actors_root.add_child(player)
	player.setup(self, info.pos)
	camera.follow(player)
	camera.snap_to(info.pos)
	intro_received.emit()
	private_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _h_you(state: Dictionary) -> void:
	var was_ghost := is_ghost()
	you = state
	if player and state.ghost and not was_ghost:
		player.set_ghost(true)
	private_changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _h_snapshot(list: Array, rem: Array, fp: PackedFloat32Array) -> void:
	if phase == Rules.Phase.ENDED:
		return
	var present := {}
	for e in list:
		var id: int = e[0]
		present[id] = true
		var v: Avatar = _views.get(id)
		if v == null:
			v = Avatar.new()
			v.actor_id = id
			_actors_root.add_child(v)
			v.setup(player_name(id), int(roster.get(id, {}).get("look", 0)))
			_views[id] = v
		v.set_flags(int(e[5]))
		v.set_target(Vector3(e[1], 0.0, e[2]), e[3], e[4])
	for id in _views:
		if not present.has(id):
			_views[id].hide_soon()
	var rem_now := {}
	for r in rem:
		var rid: int = r[0]
		rem_now[rid] = true
		if not _remain_nodes.has(rid):
			var n := Remains.new()
			n.position = Vector3(r[2], 0.0, r[3])
			add_child(n)
			n.setup(player_name(r[1]))
			_remain_nodes[rid] = n
		visible_remains[rid] = {"victim": r[1], "pos": Vector3(r[2], 0.0, r[3])}
	for rid in _remain_nodes.keys():
		if not rem_now.has(rid):
			_remain_nodes[rid].queue_free()
			_remain_nodes.erase(rid)
			visible_remains.erase(rid)
	_update_prints(fp)


@rpc("authority", "call_remote", "reliable")
func _h_lanterns(states: PackedByteArray) -> void:
	for i in mini(states.size(), _lantern_nodes.size()):
		var on := states[i] == 1
		if lit.size() > i and lit[i] != on and phase == Rules.Phase.NIGHT and player:
			var d := player.global_position.distance_to(lantern_position(i))
			if d < Rules.VIEW_RADIUS * 1.5:
				LGAudio.play_sfx(SFX_RELIGHT if on else SFX_SNUFF, -6.0 - d * 0.5, 0.1)
		lit[i] = on
		_lantern_nodes[i].set_lit(on)
	lanterns_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _h_status(p_night_left: float, done: int, total: int, _lit_count: int) -> void:
	night_left = p_night_left
	chores_done = done
	chores_total = total
	status_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _h_teleport(pos: Vector3) -> void:
	if player:
		player.teleport(pos)


@rpc("authority", "call_remote", "reliable")
func _h_denied(reason: String) -> void:
	if player:
		player.on_denied()
	if reason != "":
		toast.emit(reason)
	LGAudio.play_sfx(SFX_DENIED, -8.0)


@rpc("authority", "call_remote", "reliable")
func _h_taken(by: int) -> void:
	LGAudio.play_sfx(SFX_TAKEN)
	if player:
		player.cancel_everything()
	hud.show_banner("You were taken", "%s is Hollow. As a ghost you can still do chores, and flicker one lantern each round as a hint." % player_name(by))


@rpc("authority", "call_remote", "reliable")
func _h_seer(target: int, hollow: bool) -> void:
	var text := "%s is %s." % [player_name(target), "HOLLOW" if hollow else "not Hollow"]
	hud.show_banner("You looked closely", text)
	var v := view_of(target)
	if v:
		v.set_marked(hollow)


@rpc("authority", "call_remote", "reliable")
func _h_flicker(i: int) -> void:
	if i >= 0 and i < _lantern_nodes.size():
		_lantern_nodes[i].flicker(Rules.FLICKER_TIME)
		if player and player.global_position.distance_to(lantern_position(i)) < Rules.VIEW_RADIUS * 1.5:
			toast.emit("A lantern flickers...")


@rpc("authority", "call_remote", "reliable")
func _h_emote(id: int, n: int) -> void:
	var v: Avatar = player.avatar if id == my_id and player else _views.get(id)
	if v and EMOTES.has(n):
		v.show_emote(load(EMOTES[n]))


@rpc("authority", "call_remote", "reliable")
func _h_meeting(info: Dictionary) -> void:
	phase = Rules.Phase.MEETING
	meeting = info.duplicate()
	meeting["phase"] = Rules.MeetingPhase.DISCUSS
	meeting["voted"] = {}
	meeting["log"] = []
	if player:
		player.cancel_everything()
	for rid in _remain_nodes:
		_remain_nodes[rid].queue_free()
	_remain_nodes.clear()
	visible_remains.clear()
	LGAudio.play_sfx(SFX_BELL)
	LGAudio.play_music(MUSIC_MEETING, -6.0)
	camera.focus_meeting(_gather_center())
	meeting_started.emit(meeting)


@rpc("authority", "call_remote", "reliable")
func _h_meeting_phase(p: int, seconds: float) -> void:
	meeting["phase"] = p
	meeting_phase_changed.emit(p, seconds)


@rpc("authority", "call_remote", "reliable")
func _h_said(id: int, text: String) -> void:
	if meeting.is_empty():
		return
	meeting.log.append({"id": id, "text": text})
	meeting_said.emit(id, text)


@rpc("authority", "call_remote", "reliable")
func _h_voted(id: int) -> void:
	if meeting.is_empty():
		return
	meeting.voted[id] = true
	meeting_voted.emit(id)


@rpc("authority", "call_remote", "reliable")
func _h_meeting_result(res: Dictionary) -> void:
	meeting["phase"] = Rules.MeetingPhase.REVEAL
	meeting["result"] = res
	meeting_result.emit(res)


@rpc("authority", "call_remote", "reliable")
func _h_meeting_end() -> void:
	phase = Rules.Phase.NIGHT
	meeting = {}
	LGAudio.play_music(MUSIC_NIGHT, -4.0)
	if player:
		camera.follow(player)
	meeting_ended.emit()


@rpc("authority", "call_remote", "reliable")
func _h_game_over(res: Dictionary) -> void:
	phase = Rules.Phase.ENDED
	result = res
	if player:
		player.cancel_everything()
	var mine := Rules.team_of(role) == int(res.winner)
	LGAudio.stop_music()
	LGAudio.play_sfx("res://assets/kenney/audio/jingles/%s.ogg" % ("win" if mine else "lose"))
	game_over.emit(res)


# --- Visuals ----------------------------------------------------------------

func _gather_center() -> Vector3:
	var pts := village.gather_points(8)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)


func _make_prints() -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Footprints"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.34)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load("res://assets/kenney/light-masks/circle_a.png")
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = 256
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	return mmi


func _update_prints(fp: PackedFloat32Array) -> void:
	var mm := _prints.multimesh
	var n := mini(fp.size() / 3, mm.instance_count)
	for i in n:
		var age := fp[i * 3 + 2]
		var xf := Transform3D(Basis(), Vector3(fp[i * 3], 0.03, fp[i * 3 + 1]))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, Color(0.6, 0.85, 1.0, clampf(1.0 - age / Rules.FOOTPRINT_LIFE, 0.0, 1.0) * 0.9))
	mm.visible_instance_count = n
