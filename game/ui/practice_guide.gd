class_name PracticeGuide
extends Node
## Walks a new player through the practice round: moving, relighting a lantern,
## three chores, the map, and ringing the bell for a meeting. A glowing marker
## in the village (and an arrow at the screen edge) shows where to go.
##
## The match host sets the round up (see MatchHost.practice): everyone is a
## Lamplighter, there is no clock and one lantern starts out dark.

const WALK_DISTANCE := 8.0
const CHORES_NEEDED := 3
const STEP_NAMES := ["walk", "relight", "chores", "map", "bell", "meeting", "done"]

const GAME_HINTS := {
	"hold": "Hold the button until the bar fills.",
	"mash": "Tap the button quickly to fill the bar.",
	"timing": "Press the button when the marker is in the green zone.",
	"sequence": "Press the directions in the order shown.",
}

var game: Game
var hud: Hud

var _step := 0
var _panel: PanelContainer
var _count: Label
var _row: HBoxContainer
var _arrow: Polygon2D
var _marker: Marker
var _end: PanelContainer
var _end_ok: Button
var _walked := 0.0
var _last_pos := Vector3.INF
var _lantern := -1
var _meeting_started := false
var _meeting_over := false
var _shown_step := -1
var _shown_text := ""


class Marker extends Node3D:
	var _t := 0.0

	func _init() -> void:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.84, 0.3, 0.28)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 8.0
		cyl.material = mat
		beam.mesh = cyl
		beam.position.y = 4.0
		add_child(beam)
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1.0, 0.84, 0.3)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.2
		torus.material = ring_mat
		ring.mesh = torus
		ring.position.y = 0.08
		ring.name = "Ring"
		add_child(ring)

	func _process(delta: float) -> void:
		_t += delta
		get_node("Ring").scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 4.0))


func setup(p_game: Game, p_hud: Hud) -> void:
	game = p_game
	hud = p_hud
	_build_panel()
	_build_arrow()
	_build_end()
	_marker = Marker.new()
	_marker.visible = false
	game.add_child(_marker)
	game.meeting_started.connect(func(_i): _meeting_started = true)
	game.meeting_ended.connect(func(): _meeting_over = true)
	game.intro_received.connect(func(): _panel.visible = true)


func blocking() -> bool:
	return _end.visible


func _process(_delta: float) -> void:
	if game.player == null or _end.visible:
		return
	_update_walk()
	_advance_if_done()
	if STEP_NAMES[_step] == "done":
		_finish()
		return
	var info := _current()
	_show(info)
	_point_at(info.get("target", Vector3.INF))


func _update_walk() -> void:
	if game.player == null:
		return
	var p := game.player.global_position
	if _last_pos != Vector3.INF:
		_walked += _last_pos.distance_to(p)
	_last_pos = p


func _chores_done() -> int:
	var n := 0
	for c in game.you.get("chores", []):
		if c[2]:
			n += 1
	return n


## Text, prompt and marker target for the current step.
func _current() -> Dictionary:
	match STEP_NAMES[_step]:
		"walk":
			return {"text": "Walk around with the stick.", "action": "move_up"}
		"relight":
			if _lantern < 0:
				for i in game.lit.size():
					if not game.lit[i]:
						_lantern = i
						break
			if _lantern < 0:
				return {"text": "Look around the village."}
			return {"text": "A lantern went dark! Stand next to it and hold to relight.", "action": "interact", "target": game.lantern_position(_lantern)}
		"chores":
			var chore := game.current_chore()
			if chore.is_empty():
				return {"text": "All chores done."}
			var kind: String = chore.data.game
			var text := "%s\n%s" % [Rules.CHORES[chore.key].label, GAME_HINTS.get(kind, "")]
			return {"text": text, "action": "interact", "target": game.station_position(chore.data.station)}
		"map":
			return {"text": "Open the map.", "action": "show_map"}
		"bell":
			return {"text": "Walk to the bell in the square and ring it to call a meeting.", "action": "ring_bell", "target": game.village.bell_position()}
		"meeting":
			return {"text": "Say something with quick chat, then vote or skip. Your vote is secret."}
	return {"text": ""}


func _advance_if_done() -> void:
	var done := false
	match STEP_NAMES[_step]:
		"walk":
			done = _walked >= WALK_DISTANCE
		"relight":
			done = _lantern >= 0 and game.lit[_lantern]
		"chores":
			done = _chores_done() >= CHORES_NEEDED
		"map":
			done = hud.map.visible
		"bell":
			done = _meeting_started
		"meeting":
			done = _meeting_over
	if done:
		_step += 1
		LGAudio.play_sfx("res://assets/kenney/audio/sfx/confirmation_001.ogg", -8.0)


func _show(info: Dictionary) -> void:
	var text: String = info.get("text", "")
	var action: String = info.get("action", "")
	var target: Vector3 = info.get("target", Vector3.INF)
	if target != Vector3.INF and game.player:
		text += "  (%d m)" % int(game.player.global_position.distance_to(target))
	if _shown_step == _step and _shown_text == text:
		return
	_shown_step = _step
	_shown_text = text
	_count.text = "Practice %d / %d" % [_step + 1, STEP_NAMES.size() - 1]
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	if action != "":
		_row.add_child(ActionPrompt.make(action, text, 36))
	else:
		_row.add_child(LGUi.label(text))


func _point_at(target: Vector3) -> void:
	_marker.visible = target != Vector3.INF
	_arrow.visible = false
	if target == Vector3.INF or game.hud.blocks_input():
		return
	_marker.global_position = Vector3(target.x, 0.0, target.z)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var aim := target + Vector3(0.0, 1.0, 0.0)
	var behind := cam.is_position_behind(aim)
	var screen := cam.unproject_position(aim)
	var area := hud.root.size
	if not behind and Rect2(Vector2.ZERO, area).grow(-70.0).has_point(screen):
		return
	var center := area * 0.5
	var dir := screen - center
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2.UP
	var reach := minf((center.x - 50.0) / maxf(absf(dir.x), 0.001), (center.y - 50.0) / maxf(absf(dir.y), 0.001))
	_arrow.position = center + dir * reach
	_arrow.rotation = dir.angle() + PI * 0.5
	_arrow.visible = true


func _finish() -> void:
	_panel.visible = false
	_arrow.visible = false
	_marker.visible = false
	_end.visible = true
	_end_ok.grab_focus.call_deferred()


# --- Building --------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "GlassPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.position.y = 78
	_panel.visible = false
	hud.root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_panel.add_child(col)
	_count = LGUi.label("", "HintLabel")
	col.add_child(_count)
	_row = HBoxContainer.new()
	col.add_child(_row)


func _build_arrow() -> void:
	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(0, -24), Vector2(18, 16), Vector2(-18, 16)])
	_arrow.color = Color("ffd54a")
	_arrow.visible = false
	hud.root.add_child(_arrow)


func _build_end() -> void:
	_end = PanelContainer.new()
	_end.theme_type_variation = "ParchmentPanel"
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end.visible = false
	hud.root.add_child(_end)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 600
	_end.add_child(col)
	var title := LGUi.label("Practice complete!", "InkTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var text := LGUi.label("In a real game one or two of the villagers are secretly Hollow. Keep the lanterns lit, finish your chores, and use the meetings to work out who to trust.", "InkLabel")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_end_ok = LGUi.button("Play a game with bots", func():
		Session.start_solo(5)
		LGScenes.change_scene("res://game/ui/lobby.tscn"), 380)
	row.add_child(_end_ok)
	row.add_child(LGUi.button("Back to the menu", func(): Session.leave(""), 380))
