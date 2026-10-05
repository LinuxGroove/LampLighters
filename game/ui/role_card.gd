class_name RoleCard
extends Control
## Your role at the start of a match: the goal, what each button does for this
## role, and a tip. Dismiss it with A. It closes by itself after a while so a
## slow reader isn't left standing in the dark. Reopen it from the pause menu.

signal dismissed

const AUTO_CLOSE := 25.0

var _name: Label
var _goal: Label
var _allies: Label
var _abilities: VBoxContainer
var _tip: Label
var _ok: Button
var _left := 0.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ParchmentPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 640
	panel.add_child(col)
	var small := LGUi.label("You are", "InkLabel")
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(small)
	_name = LGUi.label("", "InkTitle")
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name)
	_goal = LGUi.label("", "InkLabel")
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_goal)
	_allies = LGUi.label("", "InkLabel")
	_allies.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_allies)
	_abilities = VBoxContainer.new()
	_abilities.add_theme_constant_override("separation", 6)
	col.add_child(_abilities)
	_tip = LGUi.label("", "InkLabel")
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.modulate = Color(1, 1, 1, 0.75)
	col.add_child(_tip)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_ok = LGUi.button("Got it", close, 240)
	row.add_child(_ok)


## `allies` are the names of the other Hollow, shown to a Hollow player.
func show_role(role: int, allies: Array = []) -> void:
	var card: Dictionary = Rules.ROLE_CARDS[role]
	_name.text = Rules.ROLE_NAMES[role]
	_name.add_theme_color_override("font_color", Color("8b1f1f") if role == Rules.Role.HOLLOW else Color("7a5200"))
	_goal.text = card.goal
	_allies.visible = role == Rules.Role.HOLLOW and not allies.is_empty()
	_allies.text = "Your fellow Hollow: %s." % ", ".join(allies)
	for c in _abilities.get_children():
		_abilities.remove_child(c)
		c.queue_free()
	for pair in card.abilities:
		var holder := PanelContainer.new()
		holder.theme_type_variation = "GlassPanel"
		holder.add_child(ActionPrompt.make(pair[0], pair[1], 32))
		_abilities.add_child(holder)
	_tip.text = card.tip
	_left = AUTO_CLOSE
	visible = true
	_ok.grab_focus.call_deferred()


func close() -> void:
	if visible:
		visible = false
		dismissed.emit()


func _process(delta: float) -> void:
	if visible:
		_left -= delta
		if _left <= 0.0:
			close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()
