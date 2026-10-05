class_name PauseMenu
extends Control
## The pause menu. The night carries on for everyone else while it's open.

var game: Game
var _col: VBoxContainer
var _help: Label


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DarkPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	panel.add_child(_col)
	_col.add_child(LGUi.label("Paused", "HeaderMedium"))
	var hint := LGUi.label("The night goes on for everyone else.", "HintLabel")
	_col.add_child(hint)
	_col.add_child(LGUi.button("Resume", close))
	_col.add_child(LGUi.button("Controls", func(): _help.visible = not _help.visible))
	var leave := LGUi.button("Leave the game", func(): Session.leave(""))
	leave.theme_type_variation = "DangerButton"
	_col.add_child(leave)
	_help = LGUi.label("", "HintLabel")
	_help.visible = false
	_col.add_child(_help)


func open() -> void:
	visible = true
	var lines := []
	for pair in [["move_up", "Move (stick or WASD)"], ["interact", "Relight, do a chore, report"],
			["special", "Hollow: snuff or take. Seer: look closely. Ghost: flicker"],
			["ring_bell", "Ring the bell at the square"], ["show_map", "Map"],
			["emote_1", "Emotes (D-pad or 1-4)"], ["pause", "Pause"]]:
		lines.append("%s   %s" % [LGInput.label_for_action(pair[0]), pair[1]])
	_help.text = "\n".join(lines)
	LGUi.focus_first(_col)


func close() -> void:
	visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
