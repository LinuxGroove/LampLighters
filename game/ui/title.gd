extends Node
## The title screen: play with bots, host or join on the local network, play
## online through the shared server, settings and quit.

const LOBBY := "res://game/ui/lobby.tscn"

## Shown once when arriving here, e.g. why the last game ended.
var message := ""

var _ui: Control
var _col: VBoxContainer
var _status: Label
var _hosts_box: VBoxContainer


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
	Session.status.connect(func(t): _status.text = t)
	Session.hosts_found.connect(_on_hosts)
	LGAudio.play_music("res://assets/kenney/audio/music/sad_descent.ogg", -6.0)
	if str(LGSettings.get_value("player", "name")).strip_edges() == "":
		_show_name(true)
	else:
		_show_main()


func _clear() -> void:
	for c in _col.get_children():
		c.queue_free()
	_hosts_box = null


func _add_title() -> void:
	var title := LGUi.label("Lantern Out", "HeaderLarge")
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
	_col.add_child(LGUi.button("Play with bots", _play_solo))
	_col.add_child(LGUi.button("Host on this network", _host_lan))
	_col.add_child(LGUi.button("Join on this network", _show_join))
	_col.add_child(LGUi.button("Play online", _show_online))
	_col.add_child(LGUi.button("Settings", func(): _show_settings()))
	_col.add_child(LGUi.button("Your name: %s" % Session.player_name(), func(): _show_name(false)))
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
		_show_main()
	edit.text_submitted.connect(func(_t): save.call())
	_col.add_child(LGUi.button("OK", save))
	if not first_time:
		_col.add_child(LGUi.button("Back", _show_main))
	edit.grab_focus.call_deferred()


func _play_solo() -> void:
	Session.start_solo(5)
	LGScenes.change_scene(LOBBY)


func _host_lan() -> void:
	if Session.host_lan():
		LGScenes.change_scene(LOBBY)


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
		if Session.join_lan_code(code.text):
			_wait_for_join()
	code.text_submitted.connect(func(_t): join.call())
	_col.add_child(LGUi.button("Join with code", join))
	_col.add_child(LGUi.button("Back", func():
		Session.stop_browsing()
		_show_main()))
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
			if Session.join_lan(str(h.address), int(h.get("port", LGSettings.get_value("lan", "port")))):
				_wait_for_join())
		b.disabled = playing or int(h.get("protocol", 0)) != GameConfig.PROTOCOL
		_hosts_box.add_child(b)


func _wait_for_join() -> void:
	_status.text = "Joining..."
	var result: Array = await _first_of_joined_or_left()
	if result[0] == "joined":
		LGScenes.change_scene(LOBBY)
	else:
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
	_col.add_child(LGUi.button("Host an online room", func():
		_status.text = "Connecting..."
		if await Session.host_online():
			LGScenes.change_scene(LOBBY)))
	var code := LineEdit.new()
	code.placeholder_text = "Room code"
	code.max_length = 8
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	_col.add_child(LGUi.button("Join with code", func():
		_status.text = "Connecting..."
		if await Session.join_online(code.text):
			_wait_for_join()))
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	LGUi.focus_first(_col)


func _show_settings() -> void:
	_clear()
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	var panel := SettingsPanel.new()
	_col.add_child(panel)
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)
