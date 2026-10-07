extends Node
## The title screen: how to play (tutorial and practice), play with bots,
## local network play, online play and leaderboards, settings and quit.

const LOBBY := "res://game/ui/lobby.tscn"

## Shown once when arriving here, e.g. why the last game ended.
var message := ""

var _ui: Control
var _col: VBoxContainer
var _status: Label
var _hosts_box: VBoxContainer
var _about_scroll: ScrollContainer
## Quick match: the search timer's label and when the search began (msec).
var _search_label: Label
var _search_since := 0
## The last status message, kept so it survives a screen change.
var _last_status := ""
## Controls on this screen that need a network, and the line saying why
## they're off while there's none (see _watch_network).
var _net_controls: Array = []
var _net_label: Label
var _net_up := true
var _net_check_at := 0
## Set once a button has started leaving this screen (or a join is under
## way), so a double press can't start a second session or scene change.
var _leaving := false


func _ready() -> void:
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.08, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var version := LGUi.label("v%s" % GameConfig.version(), "HintLabel")
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.position = Vector2(-12, -8)
	_ui.add_child(version)
	_col = LGUi.centered_column(_ui, 560)
	# Methods, not lambdas: a lambda stays connected to the autoload after this
	# screen is freed and would keep running.
	Session.status.connect(_on_status)
	Session.hosts_found.connect(_on_hosts)
	LGAudio.play_music("res://assets/kenney/audio/music/sad_descent.ogg", -6.0)
	if str(LGSettings.get_value("player", "name")).strip_edges() == "":
		_show_name(true)
	elif not bool(LGSettings.get_value("tutorial", "welcomed", false)):
		_show_welcome()
	else:
		_show_main()


func _on_status(text: String) -> void:
	_last_status = text
	if _status and is_instance_valid(_status):
		_status.text = text


func _clear() -> void:
	# Detach before freeing: queue_free alone leaves the old buttons in the tree
	# until frame end, so focus_first would grab one that is about to vanish.
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_hosts_box = null
	_about_scroll = null
	_search_label = null
	_search_since = 0
	_net_controls = []
	_net_label = null


func _add_title() -> void:
	var title := LGUi.label("Graveyard Hollow", "HeaderLarge")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("ffd27a"))
	_col.add_child(title)
	var tag := LGUi.label("Keep the lanterns lit until dawn.\nOne of your friends is blowing them out.", "HintLabel")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(tag)


func _add_status(text := "") -> void:
	_status = LGUi.label(text, "HintLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(_status)


func _show_main() -> void:
	_clear()
	_add_title()
	_col.add_child(LGUi.button("How to play", _show_howto_menu))
	_col.add_child(LGUi.button("Play with bots", _play_solo))
	_col.add_child(LGUi.button("Local network play", _show_local))
	_col.add_child(LGUi.button("Play online", _show_online))
	_col.add_child(LGUi.button("Settings", func(): _show_settings()))
	_col.add_child(LGUi.button("Your name: %s" % Session.player_name(), func(): _show_name(false)))
	_col.add_child(LGUi.button("About Graveyard Hollow", _show_about))
	var quit := LGUi.button("Quit", func(): get_tree().quit())
	quit.theme_type_variation = "DangerButton"
	_col.add_child(quit)
	_add_status(message)
	message = ""
	LGUi.focus_first(_col)


func _show_name(first_time: bool) -> void:
	_clear()
	_add_title()
	_col.add_child(LGUi.label("What should the village call you?", "HeaderMedium"))
	var edit := LineEdit.new()
	edit.max_length = 16
	edit.placeholder_text = "Your name"
	edit.text = str(LGSettings.get_value("player", "name"))
	edit.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(edit)
	_col.add_child(edit)
	var save := func():
		var n := edit.text.strip_edges()
		if n == "":
			n = "Villager %d" % randi_range(10, 99)
		LGSettings.set_value("player", "name", n)
		if first_time:
			LGSettings.set_value("player", "look", randi() % GameConfig.LOOKS.size())
		if not bool(LGSettings.get_value("tutorial", "welcomed", false)):
			_show_welcome()
		else:
			_show_main()
	edit.text_submitted.connect(func(_t): save.call())
	_col.add_child(LGUi.button("OK", save))
	if not first_time:
		_col.add_child(LGUi.button("Back", _show_main))
	edit.grab_focus.call_deferred()


## Shrinks the menu column to fit short screens, so every button stays on
## screen (the title menu and settings are taller than some handhelds).
func _process(_delta: float) -> void:
	if not _net_controls.is_empty() and Time.get_ticks_msec() >= _net_check_at:
		_apply_network(false)
	if _search_label and is_instance_valid(_search_label) and _search_since > 0:
		var secs := (Time.get_ticks_msec() - _search_since) / 1000
		_search_label.text = "Looking for players... %d:%02d" % [secs / 60, secs % 60]
	if _col == null:
		return
	var avail := get_viewport().get_visible_rect().size - Vector2(32, 48)
	var need := _col.get_combined_minimum_size()
	var s := 1.0
	if need.y > 0.0 and need.x > 0.0:
		s = clampf(minf(avail.y / need.y, avail.x / need.x), 0.5, 1.0)
	if not is_equal_approx(_col.scale.x, s):
		_col.scale = Vector2(s, s)
	_col.pivot_offset = _col.size / 2.0


## Claims the screen for one action that leaves it; false if one is running.
func _claim() -> bool:
	if _leaving or LGScenes.is_busy():
		return false
	_leaving = true
	return true


func _play_practice() -> void:
	if _claim():
		Session.start_practice()


func _show_howto_menu() -> void:
	_clear()
	_col.add_child(LGUi.label("How to play", "HeaderMedium"))
	_col.add_child(LGUi.button("Tutorial", _show_tutorial))
	_col.add_child(LGUi.button("Practice round", _play_practice))
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


## The pages open over the menu, which hides so focus stays on the pages.
func _show_tutorial() -> void:
	_col.visible = false
	var panel := HowToPanel.new()
	_ui.add_child(panel)
	panel.closed.connect(func():
		panel.queue_free()
		_col.visible = true
		LGUi.focus_first(_col))
	panel.open()


## Shown once the first time the menu appears: offers the tour and practice.
func _show_welcome() -> void:
	LGSettings.set_value("tutorial", "welcomed", true)
	_clear()
	_add_title()
	var l := LGUi.label("New here? Start with the tutorial: a few pages on the goal and the controls. Then try the practice round, with no pressure.", "HintLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(l)
	_col.add_child(LGUi.button("Tutorial", func():
		_show_howto_menu()
		_show_tutorial()))
	_col.add_child(LGUi.button("Practice round", _play_practice))
	_col.add_child(LGUi.button("Not now", _show_main))
	LGUi.focus_first(_col)


func _play_solo() -> void:
	if not _claim():
		return
	Session.start_solo(5)
	LGScenes.change_scene(LOBBY)


func _show_local() -> void:
	_clear()
	_col.add_child(LGUi.label("Local network play", "HeaderMedium"))
	_col.add_child(LGUi.label("Play with others on the same Wi-Fi or wired network.", "HintLabel"))
	var host := LGUi.button("Host on this network", _host_lan)
	var join := LGUi.button("Join on this network", _show_join)
	_col.add_child(host)
	_col.add_child(join)
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	_watch_network([host, join], "You're not connected to a network. Connect to Wi-Fi or plug in a network cable to play with others nearby.")
	LGUi.focus_first(_col)


## Turns `controls` off, with `offline_text` under the screen's header, while
## this device has no network, and back on when it has one again.
func _watch_network(controls: Array, offline_text: String) -> void:
	_net_controls = controls
	_net_label = LGUi.label(offline_text, "HintLabel")
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_label.add_theme_color_override("font_color", Color("ffd27a"))
	_col.add_child(_net_label)
	_col.move_child(_net_label, 1)
	_apply_network(true)


func _apply_network(force: bool) -> void:
	_net_check_at = Time.get_ticks_msec() + 1000
	var up := LGNetwork.is_up()
	if up == _net_up and not force:
		return
	_net_up = up
	_net_label.visible = not up
	for c in _net_controls:
		if c is BaseButton:
			c.disabled = not up
		elif c is LineEdit:
			c.editable = up
		c.focus_mode = Control.FOCUS_ALL if up else Control.FOCUS_NONE
	var focused := get_viewport().gui_get_focus_owner()
	if not force and (focused == null or focused in _net_controls or up):
		LGUi.focus_first(_col)


func _host_lan() -> void:
	if not _claim():
		return
	if Session.host_lan():
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false


func _show_join() -> void:
	_clear()
	_col.add_child(LGUi.label("Join on this network", "HeaderMedium"))
	_col.add_child(LGUi.label("Games hosted nearby show up here.", "HintLabel"))
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 8)
	_col.add_child(_hosts_box)
	_on_hosts([])
	_col.add_child(LGUi.label("Or type the host's join code:", "HintLabel"))
	var code := LineEdit.new()
	code.placeholder_text = "ABCD-EFGH"
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	var join := func():
		if not _claim():
			return
		if Session.join_lan_code(code.text):
			_wait_for_join()
		else:
			_leaving = false
	code.text_submitted.connect(func(_t): join.call())
	_col.add_child(LGUi.button("Join with code", join))
	_col.add_child(LGUi.button("Back", func():
		Session.stop_browsing()
		_show_local()))
	_add_status()
	Session.browse_lan()
	LGUi.focus_first(_col)


func _on_hosts(hosts: Array) -> void:
	if _hosts_box == null or not is_instance_valid(_hosts_box):
		return
	for c in _hosts_box.get_children():
		c.queue_free()
	if hosts.is_empty():
		_hosts_box.add_child(LGUi.label("Looking for games...", "HintLabel"))
		return
	for h in hosts:
		var playing := str(h.get("state", "lobby")) != "lobby"
		var text := "%s  (%d/%d)%s" % [h.get("name", "A village"), int(h.get("players", 0)), int(h.get("max", 10)), "  playing" if playing else ""]
		var b := LGUi.button(text, func():
			if not _claim():
				return
			if Session.join_lan(str(h.address), int(h.get("port", LGSettings.get_value("lan", "port")))):
				_wait_for_join()
			else:
				_leaving = false)
		b.disabled = playing or int(h.get("protocol", 0)) != GameConfig.PROTOCOL
		_hosts_box.add_child(b)


func _wait_for_join() -> void:
	_status.text = "Joining..."
	var result: Array = await _first_of_joined_or_left()
	if result[0] == "joined":
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false
		_status.text = str(result[1]) if str(result[1]) != "" else "Couldn't join."


func _first_of_joined_or_left() -> Array:
	var out := []
	var on_joined := func(): if out.is_empty(): out.append_array(["joined", ""])
	var on_left := func(reason: String): if out.is_empty(): out.append_array(["left", reason])
	Session.joined.connect(on_joined)
	Session.left.connect(on_left)
	var waited := 0.0
	while out.is_empty() and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	Session.joined.disconnect(on_joined)
	Session.left.disconnect(on_left)
	if out.is_empty():
		Session.leave()
		return ["left", "The host didn't answer."]
	return out


func _show_online() -> void:
	_clear()
	_col.add_child(LGUi.label("Play online", "HeaderMedium"))
	if not LGOnline.is_enabled():
		var info := LGUi.label("Online play goes through a LinuxGroove game server. Add its address in Settings to turn it on.", "HintLabel")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(info)
		_col.add_child(LGUi.button("Settings", func(): _show_settings()))
		_col.add_child(LGUi.button("Back", _show_main))
		LGUi.focus_first(_col)
		return
	var info2 := LGUi.label("Online games work best with a voice call running, since meetings are spoken.", "HintLabel")
	info2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(info2)
	var quick := LGUi.button("Quick match", _quick_match)
	_col.add_child(quick)
	var host := LGUi.button("Host an online room", func():
		if not _claim():
			return
		_status.text = "Connecting..."
		if await Session.host_online():
			LGScenes.change_scene(LOBBY)
		else:
			_leaving = false)
	_col.add_child(host)
	var code := LineEdit.new()
	code.placeholder_text = "Room code"
	code.max_length = 8
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	var join := LGUi.button("Join with code", func():
		if not _claim():
			return
		_status.text = "Connecting..."
		if await Session.join_online(code.text):
			_wait_for_join()
		else:
			_leaving = false)
	_col.add_child(join)
	var boards := LGUi.button("Leaderboards", _show_leaderboards)
	_col.add_child(boards)
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	_watch_network([quick, host, code, join, boards], LGNetwork.OFFLINE_TEXT)
	LGUi.focus_first(_col)


## Looks for other players; with nobody around after a minute, it's bots.
func _quick_match() -> void:
	if not _claim():
		return
	_clear()
	_col.add_child(LGUi.label("Quick match", "HeaderMedium"))
	_search_label = LGUi.label("Connecting...")
	_search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_search_label)
	var hint := LGUi.label("If nobody turns up within a minute, you'll play with bots instead.", "HintLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(hint)
	_col.add_child(LGUi.button("Cancel", Session.cancel_quick_match))
	LGUi.focus_first(_col)
	_search_since = Time.get_ticks_msec()
	var where: String = await Session.quick_match()
	_search_since = 0
	match where:
		"lobby":
			LGScenes.change_scene(LOBBY)
			return
		"joining":
			if _search_label and is_instance_valid(_search_label):
				_search_label.text = "Found a game. Joining..."
			var result: Array = await _first_of_joined_or_left()
			if result[0] == "joined":
				LGScenes.change_scene(LOBBY)
				return
			_last_status = str(result[1]) if str(result[1]) != "" else "Couldn't join."
	_leaving = false
	var message := _last_status
	_show_online()
	if _status:
		_status.text = message


func _show_leaderboards() -> void:
	_clear()
	_col.add_child(LGUi.label("Leaderboards", "HeaderMedium"))
	_col.add_child(LGUi.label("Rounds won in online games.", "HintLabel"))
	var panel := LGLeaderboardPanel.new()
	panel.setup(GameConfig.GAME_ID, Session.player_name(), [["wins_weekly", "This week"], ["wins", "All time"]], record_text)
	_col.add_child(panel)
	_col.add_child(LGUi.button("Back", _show_online))
	LGUi.focus_first(_col)


## The player's online record, from the stats the server keeps per round.
static func record_text(stats: Dictionary) -> String:
	var rounds := int(stats.get("rounds", 0))
	if rounds == 0:
		return "No online rounds yet. Finish one to start your record."
	return "Your online record: %s, %s (%d as a Lamplighter, %d as the Hollow), survived %d." % [
		_count(rounds, "round"), _count(int(stats.get("wins", 0)), "win"),
		int(stats.get("village_wins", 0)), int(stats.get("hollow_wins", 0)),
		int(stats.get("survived", 0)),
	]


static func _count(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]


func _show_settings() -> void:
	_clear()
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	var panel := SettingsPanel.new()
	_col.add_child(panel)
	for row in [["Role card at start", "role_card"], ["Tips during play", "hints"]]:
		var key: String = row[1]
		var c := LGCycler.make(row[0], SettingsPanel.ON_OFF, LGSettings.get_value("tutorial", key, true), func(v):
			LGSettings.set_value("tutorial", key, v))
		panel.add_child(c)
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


## Credits. Up and down scroll the page, since Back is the only button.
func _show_about() -> void:
	_clear()
	_col.add_child(LGUi.label("About Graveyard Hollow", "HeaderMedium"))
	_about_scroll = ScrollContainer.new()
	_about_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_about_scroll.custom_minimum_size = Vector2(620, 520)
	_col.add_child(_about_scroll)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GlassPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_about_scroll.add_child(panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = ABOUT_TEXT % GameConfig.version()
	panel.add_child(text)
	var back := LGUi.button("Back", _show_main)
	_col.add_child(back)
	back.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if _about_scroll == null or not is_instance_valid(_about_scroll):
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0:
		_about_scroll.scroll_vertical += step * 60
		get_viewport().set_input_as_handled()


const ABOUT_TEXT := """[center][b]Graveyard Hollow[/b]  v%s
A LinuxGroove game

[b]Created by[/b]
Drew VanDine
Kaden VanDine
Ken VanDine

[b]Art, sound, music and fonts[/b]
Kenney (kenney.nl)
Released under CC0. Thank you, Kenney!

Mini Characters, Graveyard Kit, Fantasy Town Kit, Survival Kit,
Cube Pets, Food Kit, Light Masks, Emote Pack, Input Prompts,
UI Pack - Adventure, Kenney Fonts, Music Loops, RPG Audio,
Impact Sounds, Interface Sounds, Music Jingles

[b]Made with[/b]
Godot Engine (godotengine.org), MIT
Nakama Godot client by Heroic Labs, Apache-2.0
Lemonade Server (lemonade-sdk), Apache-2.0, for AI players

AI players' language models download on first use
under their own licenses.

Copyright (c) 2026 The LinuxGroove team
Graveyard Hollow is free software under the MIT license.[/center]"""
