class_name ChoreGame
extends PanelContainer
## The little chore games, all playable with one hand on a controller:
##   hold      hold A until the bar fills
##   mash      tap A quickly to fill the bar before it drains
##   timing    press A when the moving marker is inside the green zone, 3 times
##   sequence  press the shown directions in order

const HITS_NEEDED := 3
const SEQUENCE_LENGTH := 4
const DIRS := ["chore_up", "chore_right", "chore_down", "chore_left"]

var kind := "hold"
var progress := 0.0
var _min_time := 1.0
var _hold_time := 2.0
var _elapsed := 0.0
var _hits := 0
var _zone := Vector2(0.4, 0.6)
var _marker := 0.0
var _seq: Array = []
var _seq_i := 0
var _on_done := Callable()

var _title: Label
var _bar: ProgressBar
var _prompt: ActionPrompt
var _cancel_prompt: ActionPrompt
var _track: Control
var _seq_row: HBoxContainer


func _ready() -> void:
	theme_type_variation = "ParchmentPanel"
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(560, 300)
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	_title = LGUi.label("", "InkHeader")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_track = Control.new()
	_track.custom_minimum_size = Vector2(500, 46)
	_track.draw.connect(_draw_track)
	col.add_child(_track)
	_seq_row = HBoxContainer.new()
	_seq_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_seq_row.add_theme_constant_override("separation", 18)
	col.add_child(_seq_row)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(500, 26)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	col.add_child(_bar)
	var prompts := HBoxContainer.new()
	prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	prompts.add_theme_constant_override("separation", 30)
	col.add_child(prompts)
	var p1 := PanelContainer.new()
	p1.theme_type_variation = "GlassPanel"
	_prompt = ActionPrompt.make("interact", "", 36)
	p1.add_child(_prompt)
	prompts.add_child(p1)
	var p2 := PanelContainer.new()
	p2.theme_type_variation = "GlassPanel"
	_cancel_prompt = ActionPrompt.make("cancel", "Stop", 36)
	p2.add_child(_cancel_prompt)
	prompts.add_child(p2)


func open(chore: Dictionary, on_done: Callable) -> void:
	var step: Dictionary = chore.data
	kind = str(step.get("game", "hold"))
	_min_time = float(step.get("min", 1.0))
	_hold_time = float(step.get("time", 2.0))
	_on_done = on_done
	_elapsed = 0.0
	progress = 0.0
	_hits = 0
	_title.text = Rules.CHORES[chore.key].label
	_track.visible = kind == "timing"
	_seq_row.visible = kind == "sequence"
	match kind:
		"hold":
			_prompt.set_action("interact", "Hold")
		"mash":
			_prompt.set_action("interact", "Tap quickly")
		"timing":
			_prompt.set_action("interact", "Tap in the green zone")
			_new_zone()
		"sequence":
			_prompt.set_action("chore_up", "Press the directions in order")
			_new_sequence()
	_bar.value = 0.0
	visible = true


func close() -> void:
	if visible:
		visible = false
		var cb := _on_done
		_on_done = Callable()
		if cb.is_valid():
			cb.call(false)


func _finish(done: bool) -> void:
	visible = false
	var cb := _on_done
	_on_done = Callable()
	if cb.is_valid():
		cb.call(done)
	if done:
		LGAudio.play_sfx("res://assets/kenney/audio/sfx/confirmation_001.ogg", -4.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	match kind:
		"hold":
			if Input.is_action_pressed("interact"):
				progress = minf(1.0, progress + delta / _hold_time)
		"mash":
			# A full bar waits out the minimum time instead of draining back.
			if progress < 1.0:
				progress = maxf(0.0, progress - delta * 0.18)
		"timing":
			_marker = (sin(_elapsed * 2.8) + 1.0) * 0.5
			_track.queue_redraw()
	_bar.value = progress
	if progress >= 1.0 and _elapsed >= _min_time:
		_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	match kind:
		"mash":
			if event.is_action_pressed("interact"):
				get_viewport().set_input_as_handled()
				progress = minf(1.0, progress + 0.12)
				LGAudio.play_sfx("res://assets/kenney/audio/sfx/impactWood_light_000.ogg", -10.0, 0.15)
		"timing":
			if event.is_action_pressed("interact"):
				get_viewport().set_input_as_handled()
				if _marker >= _zone.x and _marker <= _zone.y:
					_hits += 1
					LGAudio.play_sfx("res://assets/kenney/audio/sfx/impactPlank_medium_000.ogg", -6.0, 0.1)
					_new_zone()
				else:
					_hits = maxi(0, _hits - 1)
					LGAudio.play_sfx("res://assets/kenney/audio/sfx/error_001.ogg", -10.0)
				progress = float(_hits) / HITS_NEEDED
		"sequence":
			for i in DIRS.size():
				if event.is_action_pressed(DIRS[i]):
					get_viewport().set_input_as_handled()
					if i == _seq[_seq_i]:
						_seq_i += 1
						LGAudio.play_sfx("res://assets/kenney/audio/sfx/select_001.ogg", -8.0, 0.1)
					else:
						_seq_i = 0
						LGAudio.play_sfx("res://assets/kenney/audio/sfx/error_001.ogg", -10.0)
					progress = float(_seq_i) / _seq.size()
					_show_sequence()
					return


func _new_zone() -> void:
	var w := 0.2
	var start := randf_range(0.05, 0.95 - w)
	_zone = Vector2(start, start + w)


func _new_sequence() -> void:
	_seq.clear()
	for i in SEQUENCE_LENGTH:
		_seq.append(randi() % DIRS.size())
	_seq_i = 0
	_show_sequence()


func _show_sequence() -> void:
	for c in _seq_row.get_children():
		c.queue_free()
	for i in _seq.size():
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = LGInput.glyph_for_action(DIRS[_seq[i]])
		icon.modulate = Color(1, 1, 1, 0.3) if i < _seq_i else (Color.WHITE if i == _seq_i else Color(1, 1, 1, 0.7))
		if i == _seq_i:
			icon.custom_minimum_size = Vector2(68, 68)
		_seq_row.add_child(icon)


func _draw_track() -> void:
	var size := _track.size
	_track.draw_rect(Rect2(Vector2.ZERO, size), Color(0.23, 0.16, 0.1, 0.9))
	_track.draw_rect(Rect2(Vector2(size.x * _zone.x, 0), Vector2(size.x * (_zone.y - _zone.x), size.y)), Color("63c06b"))
	var x := size.x * _marker
	_track.draw_rect(Rect2(Vector2(x - 4, -4), Vector2(8, size.y + 8)), Color("ffd54a"))
