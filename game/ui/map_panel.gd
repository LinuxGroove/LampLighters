class_name MapPanel
extends Control
## A parchment map of the village: lanterns, the bell, your chores and you.

var game: Game
var _canvas: Control


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ParchmentPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var title := LGUi.label(game.village.map_name, "InkHeader")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(600, 600)
	_canvas.draw.connect(_draw_map)
	col.add_child(_canvas)
	var hint := PanelContainer.new()
	hint.theme_type_variation = "GlassPanel"
	hint.add_child(ActionPrompt.make("show_map", "Close", 32))
	col.add_child(hint)


func open() -> void:
	visible = true
	_canvas.queue_redraw()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_canvas.queue_redraw()


func _to_map(p: Vector3) -> Vector2:
	var b: Rect2 = game.village.bounds
	return Vector2((p.x - b.position.x) / b.size.x, (p.z - b.position.y) / b.size.y) * _canvas.size


func _draw_map() -> void:
	var ink := LGTheme.INK
	var font := _canvas.get_theme_default_font()
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(0.36, 0.5, 0.3, 0.35))
	var marks: Dictionary = game.village.landmark_positions()
	for n in marks:
		var p := _to_map(marks[n])
		_canvas.draw_string(font, p + Vector2(-40, -10), str(n).capitalize(), HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(ink, 0.75))
	for i in game.lit.size():
		var p := _to_map(game.lantern_position(i))
		if game.lit[i]:
			_canvas.draw_circle(p, 9, Color(1.0, 0.85, 0.35, 0.55))
			_canvas.draw_circle(p, 5, Color(1.0, 0.75, 0.2))
		else:
			_canvas.draw_circle(p, 5, Color(0.2, 0.2, 0.25))
	var bell := _to_map(game.village.bell_position())
	_canvas.draw_rect(Rect2(bell - Vector2(7, 7), Vector2(14, 14)), Color("b0782a"))
	var n := 1
	for c in game.available_chores():
		var sp: Vector3 = game.station_position(c.data.station)
		if sp == Vector3.INF:
			continue
		var p := _to_map(sp)
		_canvas.draw_circle(p, 11, Color("e8635a"))
		_canvas.draw_string(font, p + Vector2(-10, 6), str(n), HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color.WHITE)
		n += 1
	if game.player:
		var p := _to_map(game.player.global_position)
		var fwd := Vector2(sin(game.player.avatar.rotation.y), cos(game.player.avatar.rotation.y))
		_canvas.draw_colored_polygon(PackedVector2Array([p + fwd * 14, p + fwd.orthogonal() * 8 - fwd * 6, p - fwd.orthogonal() * 8 - fwd * 6]), Color("3b6fd8"))
		_canvas.draw_circle(p, 4, Color.WHITE)
