class_name LGCycler
extends Button
## A "Label: < value >" option row that works with a controller: left and
## right change the value while it has focus, and A steps forward.

signal value_changed(value: Variant)

var label_text := ""
var options: Array = []  # [[value, text], ...]
var index := 0
var read_only := false


static func make(p_label: String, p_options: Array, current: Variant, on_change := Callable(), width := 440) -> LGCycler:
	var c := LGCycler.new()
	c.label_text = p_label
	c.options = p_options
	c.custom_minimum_size = Vector2(width, 52)
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.set_value(current)
	if on_change.is_valid():
		c.value_changed.connect(on_change)
	c.pressed.connect(func(): c.step(1))
	return c


func value() -> Variant:
	return options[index][0] if index < options.size() else null


func set_value(v: Variant) -> void:
	index = 0
	for i in options.size():
		if options[i][0] == v:
			index = i
			break
	_refresh()


func set_read_only(on: bool) -> void:
	read_only = on
	disabled = on
	focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
	_refresh()


func step(dir: int) -> void:
	if read_only or options.is_empty():
		return
	index = wrapi(index + dir, 0, options.size())
	_refresh()
	LGUi.click()
	value_changed.emit(value())


func _gui_input(event: InputEvent) -> void:
	if read_only:
		return
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step(1)
		accept_event()


func _refresh() -> void:
	var shown: String = str(options[index][1]) if index < options.size() else ""
	text = "%s:  %s" % [label_text, shown] if read_only else "%s:  < %s >" % [label_text, shown]
