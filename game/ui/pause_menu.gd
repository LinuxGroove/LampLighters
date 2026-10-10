class_name PauseMenu
extends Control
## The pause menu. The night carries on for everyone else while it's open.

var game: Game
var _col: VBoxContainer
var _panel: PanelContainer
var _role_button: Button
var _help: Label


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DarkPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	_panel.add_child(_col)
	_col.add_child(LGUi.label("Paused", "HeaderMedium"))
	var hint := LGUi.label("The night goes on for everyone else.", "HintLabel")
	_col.add_child(hint)
	_col.add_child(LGUi.button("Resume", close))
	_col.add_child(LGPlaytestButton.make())
	_col.add_child(LGUi.button("Controls", func(): _help.visible = not _help.visible))
	_role_button = LGUi.button("My role", func(): _show_over(game.hud.show_role_card))
	_col.add_child(_role_button)
	_col.add_child(LGUi.button("Tutorial", func(): _show_over(game.hud.howto.open)))
	var leave := LGUi.button("Leave the game", func(): Session.leave(""))
	leave.theme_type_variation = "DangerButton"
	_col.add_child(leave)
	_help = LGUi.label("", "HintLabel")
	_help.visible = false
	_col.add_child(_help)


func open() -> void:
	visible = true
	_panel.visible = true
	_role_button.visible = not game.hud.practice and game.role >= 0
	var lines := []
	var pad := LGInput.is_gamepad()
	for pair in [["move_up", "Move"], ["interact", "Relight, do a chore, report"],
			["special", "Hollow: snuff or take. Seer: look closely. Ghost: flicker"],
			["ring_bell", "Ring the bell at the square"], ["show_map", "Map"],
			["emote_1", "Emotes"], ["pause", "Pause"]]:
		var key: String = "Left stick" if pad and pair[0] == "move_up" else ("D-pad" if pad and pair[0] == "emote_1" else ("WASD" if pair[0] == "move_up" else ("1-4" if pair[0] == "emote_1" else LGInput.label_for_action(pair[0]))))
		lines.append("%s   %s" % [key, pair[1]])
	_help.text = "\n".join(lines)
	LGUi.focus_first(_col)


## Opens a full-screen card from the pause menu, hiding the menu behind it so
## focus can't wander onto it, and bringing the menu back when the card closes.
func _show_over(open_card: Callable) -> void:
	_panel.visible = false
	var card: Control = game.hud.howto
	if open_card == game.hud.show_role_card:
		card = game.hud.role_card
	var back := func():
		if visible:
			_panel.visible = true
			LGUi.focus_first(_col)
	if card.has_signal("closed"):
		card.closed.connect(back, CONNECT_ONE_SHOT)
	else:
		card.dismissed.connect(back, CONNECT_ONE_SHOT)
	open_card.call()


func close() -> void:
	visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()
