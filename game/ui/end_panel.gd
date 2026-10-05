class_name EndPanel
extends Control
## Dawn (or darkness): who won, why, and everyone's secret role.

var game: Game
var _title: Label
var _reason: Label
var _list: GridContainer
var _stats: Label
var _buttons: HBoxContainer


func setup(p_game: Game) -> void:
	game = p_game
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
	panel.custom_minimum_size = Vector2(820, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_title = LGUi.label("", "InkTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_reason = LGUi.label("", "InkLabel")
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_reason)
	_list = GridContainer.new()
	_list.columns = 3
	_list.add_theme_constant_override("h_separation", 28)
	col.add_child(_list)
	_stats = LGUi.label("", "InkLabel")
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stats)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 16)
	col.add_child(_buttons)
	game.game_over.connect(open)


func open(res: Dictionary) -> void:
	visible = true
	var village_won: bool = int(res.winner) == Rules.Team.VILLAGE
	var mine := Rules.team_of(game.role) == int(res.winner)
	_title.text = ("The village wins!" if village_won else "The Hollow win!")
	_title.add_theme_color_override("font_color", Color("2f6b2f") if village_won else Color("8b1f1f"))
	_reason.text = "%s %s" % [res.reason, "You won." if mine else "You lost."]
	for c in _list.get_children():
		c.queue_free()
	var ids: Array = res.players.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = res.players[id]
		var name := LGUi.label(str(p.name) + (" (you)" if id == game.my_id else ""), "InkHeader")
		name.add_theme_font_size_override("font_size", 22)
		name.add_theme_color_override("font_color", GameConfig.look_color(int(p.look)).darkened(0.35))
		_list.add_child(name)
		var role: int = res.roles[id]
		var r := LGUi.label(Rules.ROLE_NAMES[role], "InkLabel")
		if role == Rules.Role.HOLLOW:
			r.add_theme_color_override("font_color", Color("8b1f1f"))
		_list.add_child(r)
		var fate := "left" if p.out else ("made it" if p.alive else "taken or banished")
		_list.add_child(LGUi.label(fate, "InkLabel"))
	_stats.text = "Chores %d/%d   Lanterns lit %d/%d" % [res.chores_done, res.chores_total, res.lit, res.lanterns]
	for c in _buttons.get_children():
		c.queue_free()
	if Session.is_host():
		_buttons.add_child(LGUi.button("Play again", func(): Session.restart_match(), 260))
		_buttons.add_child(LGUi.button("Back to lobby", func(): Session.return_to_lobby(), 260))
	else:
		_buttons.add_child(LGUi.label("Waiting for the host...", "InkLabel"))
		var leave := LGUi.button("Leave", func(): Session.leave(""), 200)
		leave.theme_type_variation = "DangerButton"
		_buttons.add_child(leave)
	LGUi.focus_first(_buttons)
