extends Node
## The lobby before a night: who's coming, bots, house rules, the join code,
## and the host's Start button.

const SETTING_ROWS := [
	["night_minutes", "Night length", [[5, "5 min"], [6, "6 min"], [8, "8 min"], [10, "10 min"], [12, "12 min"], [15, "15 min"]]],
	["hollow_count", "Hollow", [[0, "Automatic"], [1, "1"], [2, "2"], [3, "3"]]],
	["special_roles", "Seer and Watchman", [[true, "On"], [false, "Off"]]],
	["chores_each", "Chores each", [[2, "2"], [3, "3"], [4, "4"], [5, "5"], [6, "6"]]],
	["discussion_seconds", "Talk time", [[30, "30 s"], [45, "45 s"], [60, "60 s"], [90, "90 s"], [120, "2 min"]]],
	["vote_seconds", "Vote time", [[15, "15 s"], [20, "20 s"], [30, "30 s"], [45, "45 s"], [60, "60 s"]]],
	["reveal_on_banish", "Reveal banished role", [[true, "On"], [false, "Off"]]],
	["anonymous_votes", "Secret votes", [[true, "On"], [false, "Off"]]],
	["bell_uses", "Bell rings each", [[1, "1"], [2, "2"], [3, "3"]]],
	["ai_brains", "Bots talk with local AI", [[true, "On"], [false, "Off"]]],
]

var _roster: VBoxContainer
var _settings_box: VBoxContainer
var _cyclers := {}
var _code: Label
var _ai: Label
var _status: Label
var _start: Button
var _add_bot: Button
var _remove_bot: Button
var _look: LGCycler
var _preview: LookPreview


func _ready() -> void:
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.08, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	ui.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := LGUi.label(_title_text(), "HeaderMedium")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_code = LGUi.label("", "HeaderMedium")
	_code.add_theme_color_override("font_color", Color("ffd27a"))
	head.add_child(_code)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	col.add_child(body)
	# Players
	var left := PanelContainer.new()
	left.theme_type_variation = "DarkPanel"
	left.custom_minimum_size.x = 440
	body.add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	left.add_child(lcol)
	lcol.add_child(LGUi.label("Villagers", "HeaderMedium"))
	_roster = VBoxContainer.new()
	_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lcol.add_child(_roster)
	var bots := HBoxContainer.new()
	lcol.add_child(bots)
	_add_bot = LGUi.button("Add bot", func(): Session.add_bot(), 190)
	_remove_bot = LGUi.button("Remove bot", func(): Session.remove_bot(), 190)
	bots.add_child(_add_bot)
	bots.add_child(_remove_bot)
	var looks := []
	for i in GameConfig.LOOKS.size():
		looks.append([i, "Villager %d" % (i + 1)])
	_preview = LookPreview.make(Session.player_look(), Vector2(160, 190))
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lcol.add_child(_preview)
	_look = LGCycler.make("Your look", looks, Session.player_look(), func(v):
		_preview.set_look(v)
		Session.set_look(v), 400)
	lcol.add_child(_look)
	# House rules
	var right := PanelContainer.new()
	right.theme_type_variation = "DarkPanel"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rscroll.follow_focus = true
	right.add_child(rscroll)
	_settings_box = VBoxContainer.new()
	_settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_box.add_theme_constant_override("separation", 6)
	rscroll.add_child(_settings_box)
	_settings_box.add_child(LGUi.label("House rules", "HeaderMedium"))
	for row in SETTING_ROWS:
		var key: String = row[0]
		var c := LGCycler.make(row[1], row[2], Session.settings.get(key), func(v): Session.set_setting(key, v), 520)
		_cyclers[key] = c
		_settings_box.add_child(c)
	_ai = LGUi.label("", "HintLabel")
	_ai.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_box.add_child(_ai)
	# Bottom
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	_status = LGUi.label("", "HintLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	var leave := LGUi.button("Leave", _leave, 200)
	leave.theme_type_variation = "DangerButton"
	bottom.add_child(leave)
	_start = LGUi.button("Start the night", func(): Session.start_match(), 300)
	bottom.add_child(_start)
	Session.roster_changed.connect(_refresh)
	Session.settings_changed.connect(_refresh)
	# Methods, not lambdas: a lambda stays connected to the autoload after the
	# lobby is freed, so an old lobby would still send everyone to the title
	# screen when a later session ends.
	Session.status.connect(_on_status)
	Session.left.connect(_on_left)
	LGBrain.state_changed.connect(_on_brain_state)
	LGAudio.play_music("res://assets/kenney/audio/music/retro_mystic.ogg", -8.0)
	_refresh()
	_warm_up_ai()
	if Session.is_host():
		_start.grab_focus.call_deferred()
	else:
		_look.grab_focus.call_deferred()


func _on_status(text: String) -> void:
	_status.text = text


func _on_left(reason: String) -> void:
	LGScenes.change_scene("res://game/ui/title.tscn", func(n): n.set("message", reason))


func _on_brain_state(_state: String, _detail: String) -> void:
	_refresh_ai()


func _title_text() -> String:
	match Session.mode:
		Session.Mode.SOLO:
			return "A night with bots"
		Session.Mode.LAN_HOST, Session.Mode.ONLINE_HOST:
			return "Your village"
	return "Joined a village"


func _refresh() -> void:
	for c in _roster.get_children():
		c.queue_free()
	var ids: Array = Session.players.keys()
	ids.sort_custom(func(a, b): return (a if a > 0 else 1000 - a) < (b if b > 0 else 1000 - b))
	for id in ids:
		var p: Dictionary = Session.players[id]
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = GameConfig.look_color(int(p.look))
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var tags := []
		if p.get("bot", false):
			tags.append("bot")
		if id == 1:
			tags.append("host")
		if id == Session.local_id():
			tags.append("you")
		row.add_child(LGUi.label("  %s%s" % [p.name, ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""]))
		_roster.add_child(row)
	var host := Session.is_host()
	_add_bot.visible = host
	_remove_bot.visible = host
	_add_bot.disabled = Session.players.size() >= GameConfig.MAX_PLAYERS
	_remove_bot.disabled = not Session.players.values().any(func(p): return p.get("bot", false))
	for key in _cyclers:
		_cyclers[key].set_value(Session.settings.get(key))
		_cyclers[key].set_read_only(not host)
	_start.visible = host
	_start.disabled = not Session.can_start()
	if host and Session.players.size() < GameConfig.MIN_PLAYERS:
		_status.text = "A night needs at least %d villagers. Add bots or wait for friends." % GameConfig.MIN_PLAYERS
	elif not host:
		_status.text = "Waiting for the host to start the night."
	match Session.mode:
		Session.Mode.LAN_HOST:
			_code.text = "Join code: %s" % JoinCode.pretty(Session.join_code) if Session.join_code != "" else "No network found"
		Session.Mode.ONLINE_HOST, Session.Mode.ONLINE_CLIENT:
			_code.text = "Room code: %s" % Session.join_code
		_:
			_code.text = ""
	_refresh_ai()


func _refresh_ai() -> void:
	var has_bots: bool = Session.players.values().any(func(p): return p.get("bot", false))
	if not Session.is_host() or not has_bots:
		_ai.text = ""
		return
	if not Session.settings.get("ai_brains", true):
		_ai.text = "Bots use scripted talk in meetings."
		return
	_ai.text = SettingsPanel._ai_text(LGBrain.state, LGBrain.detail)


## Starts the local AI early so it's ready by the first meeting.
func _warm_up_ai() -> void:
	if not Session.is_host() or not Session.settings.get("ai_brains", true):
		return
	if str(LGSettings.get_value("ai", "mode")) == "off":
		return
	LGBrain.ensure_ready_async()


func _leave() -> void:
	# Session.left takes everyone back to the title screen.
	Session.leave("")
