class_name MeetingPanel
extends Control
## The meeting at the bell: who's here, what's been said, quick-chat lines,
## then a secret vote and the result. Everything is reachable with the
## D-pad and A/B as well as the mouse and keyboard.

var game: Game
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _timer: Label
var _cards: GridContainer
var _card_buttons := {}
var _skip: Button
var _log_scroll: ScrollContainer
var _log: VBoxContainer
var _chat: GridContainer
var _picker: PanelContainer
var _picker_title: Label
var _picker_grid: GridContainer
var _note: Label
var _time_left := 0.0
var _phase := Rules.MeetingPhase.DISCUSS
var _voted := false
var _last_focus: Control


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "DarkPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(1160, 680)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_title = LGUi.label("Meeting at the bell", "HeaderMedium")
	titles.add_child(_title)
	_subtitle = LGUi.label("", "HintLabel")
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)
	_timer = LGUi.label("", "HeaderMedium")
	head.add_child(_timer)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	body.add_child(left)
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 10)
	_cards.add_theme_constant_override("v_separation", 8)
	left.add_child(_cards)
	_skip = LGUi.button("Skip vote", func(): _vote(Rules.SKIP_VOTE), 250)
	left.add_child(_skip)
	_note = LGUi.label("", "HintLabel")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_note)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var log_panel := PanelContainer.new()
	log_panel.theme_type_variation = "GlassPanel"
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	_log_scroll = ScrollContainer.new()
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_panel.add_child(_log_scroll)
	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_scroll.add_child(_log)
	_chat = GridContainer.new()
	_chat.columns = 2
	right.add_child(_chat)
	_add_chat("I suspect...", func(): _pick_player("Who do you suspect?", func(a): _say(0, a, -1)))
	_add_chat("I trust...", func(): _pick_player("Who do you trust?", func(a): _say(1, a, -1)))
	_add_chat("I was near...", func(): _pick_place("Where were you?", func(p): _say(2, 0, p)))
	_add_chat("I saw someone...", func(): _pick_player("Who did you see?", func(a):
		_pick_place("Where did you see them?", func(p): _say(3, a, p))))
	_add_chat("Let's skip", func(): _say(4, 0, -1))
	_add_chat("It wasn't me!", func(): _say(5, 0, -1))
	_picker = PanelContainer.new()
	_picker.theme_type_variation = "ParchmentPanel"
	_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_picker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_picker.grow_vertical = Control.GROW_DIRECTION_BOTH
	_picker.visible = false
	add_child(_picker)
	var pcol := VBoxContainer.new()
	_picker.add_child(pcol)
	_picker_title = LGUi.label("", "InkHeader")
	pcol.add_child(_picker_title)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 3
	pcol.add_child(_picker_grid)
	game.meeting_started.connect(open)
	game.meeting_phase_changed.connect(_on_phase)
	game.meeting_said.connect(_on_said)
	game.meeting_voted.connect(func(_id): _refresh_cards())
	game.meeting_result.connect(_on_result)
	game.meeting_ended.connect(close)
	game.game_over.connect(func(_r): close())


func open(info: Dictionary) -> void:
	visible = true
	_phase = Rules.MeetingPhase.DISCUSS
	_voted = false
	_time_left = float(info.discuss)
	_picker.visible = false
	for c in _log.get_children():
		c.queue_free()
	if info.reason == "report":
		_title.text = "%s found %s's lantern" % [game.player_name(info.caller), game.player_name(info.victim)]
		_subtitle.text = "It was lying near %s. Talk it over, then vote in secret." % info.place
	else:
		_title.text = "%s rang the bell" % game.player_name(info.caller)
		_subtitle.text = "Talk it over, then vote in secret."
	var taken: Array = info.get("taken", [])
	if taken.size() > 1:
		var names := []
		for t in taken:
			names.append(game.player_name(t))
		_subtitle.text += " Taken since the last meeting: %s." % ", ".join(names)
	_build_cards(info.alive)
	_update_controls()


func close() -> void:
	visible = false
	_picker.visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time_left = maxf(0.0, _time_left - delta)
	var what := "Talk" if _phase == Rules.MeetingPhase.DISCUSS else ("Vote" if _phase == Rules.MeetingPhase.VOTE else "")
	_timer.text = "%s  %d" % [what, ceili(_time_left)] if what != "" else ""


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _picker.visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_close_picker()


# --- Cards ------------------------------------------------------------------

func _build_cards(alive: Array) -> void:
	for c in _cards.get_children():
		c.queue_free()
	_card_buttons.clear()
	var ids: Array = game.roster.keys()
	ids.sort()
	for id in ids:
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", game.player_color(id).darkened(0.45))
		b.add_theme_color_override("font_disabled_color", game.player_color(id).darkened(0.45) * Color(1, 1, 1, 0.7))
		b.set_meta("alive", id in alive)
		b.pressed.connect(_vote.bind(id))
		b.pressed.connect(func(): LGUi.click())
		_cards.add_child(b)
		_card_buttons[id] = b
	_refresh_cards()


func _refresh_cards() -> void:
	var voted: Dictionary = game.meeting.get("voted", {})
	var res: Dictionary = game.meeting.get("result", {})
	for id in _card_buttons:
		var b: Button = _card_buttons[id]
		var alive: bool = b.get_meta("alive")
		var line := game.player_name(id)
		if id == game.my_id:
			line += " (you)"
		var status := ""
		if not alive:
			status = "gone"
		elif voted.has(id):
			status = "voted"
		if not res.is_empty():
			var n := int(res.tally.get(id, 0))
			status = "%d vote%s" % [n, "" if n == 1 else "s"]
			if res.banished == id:
				status = "BANISHED, " + status
		b.text = line + ("\n   " + status if status != "" else "")
		b.disabled = not (_phase == Rules.MeetingPhase.VOTE and alive and id != game.my_id and _can_act() and not _voted)
		b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL


func _can_act() -> bool:
	return game.is_alive() and game.meeting.get("alive", []).has(game.my_id)


func _update_controls() -> void:
	var talk := _phase == Rules.MeetingPhase.DISCUSS and _can_act()
	for b in _chat.get_children():
		b.disabled = not talk
		b.focus_mode = Control.FOCUS_ALL if talk else Control.FOCUS_NONE
	_skip.visible = _phase == Rules.MeetingPhase.VOTE
	_skip.disabled = _voted or not _can_act()
	if not _can_act():
		_note.text = "Ghosts can't speak or vote. Watch, and remember."
	elif _phase == Rules.MeetingPhase.DISCUSS:
		_note.text = "Talk out loud if you're in the same room. Quick chat sends a line to everyone."
	elif _phase == Rules.MeetingPhase.VOTE:
		_note.text = "Your vote is secret." if not _voted else "Vote sent. Waiting for the others..."
	else:
		_note.text = ""
	_refresh_cards()
	_focus_something()


func _focus_something() -> void:
	if _picker.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused and is_ancestor_of(focused) and focused.focus_mode != Control.FOCUS_NONE and not (focused is BaseButton and focused.disabled):
		return
	if _phase == Rules.MeetingPhase.DISCUSS:
		LGUi.focus_first(_chat)
	elif _phase == Rules.MeetingPhase.VOTE:
		LGUi.focus_first(_cards)
		if LGUi.first_focusable(_cards) == null and not _skip.disabled:
			_skip.grab_focus.call_deferred()


# --- Talking ------------------------------------------------------------------

func _add_chat(text: String, cb: Callable) -> void:
	var b := LGUi.button(text, cb, 270)
	_chat.add_child(b)


func _say(kind: int, a: int, place: int) -> void:
	game.to_host("_c_say", [kind, a, place])


func _on_said(id: int, text: String) -> void:
	var row := HBoxContainer.new()
	var who := LGUi.label(game.player_name(id) + ":", "NameLabel")
	who.add_theme_color_override("font_color", game.player_color(id).lightened(0.25))
	row.add_child(who)
	var what := LGUi.label(text)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.custom_minimum_size.x = 300
	row.add_child(what)
	_log.add_child(row)
	LGAudio.play_sfx("res://assets/kenney/audio/sfx/pluck_001.ogg", -12.0, 0.1)
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _pick_player(title: String, cb: Callable) -> void:
	var items := []
	var ids: Array = game.meeting.get("alive", [])
	for id in ids:
		if id != game.my_id:
			items.append([game.player_name(id), id])
	_open_picker(title, items, cb)


func _pick_place(title: String, cb: Callable) -> void:
	var items := []
	for i in game.landmarks.size():
		items.append([game.landmarks[i].capitalize(), i])
	_open_picker(title, items, cb)


func _open_picker(title: String, items: Array, cb: Callable) -> void:
	_last_focus = get_viewport().gui_get_focus_owner()
	for c in _picker_grid.get_children():
		c.queue_free()
	_picker_title.text = title
	for item in items:
		var value: Variant = item[1]
		var b := LGUi.button(item[0], func():
			_close_picker()
			cb.call(value), 220)
		_picker_grid.add_child(b)
	var back := LGUi.button("Back", _close_picker, 220)
	back.theme_type_variation = "DangerButton"
	_picker_grid.add_child(back)
	_picker.visible = true
	LGUi.focus_first(_picker_grid)


func _close_picker() -> void:
	_picker.visible = false
	if _last_focus and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus.call_deferred()
	else:
		_focus_something()


# --- Voting ----------------------------------------------------------------------

func _on_phase(p: int, seconds: float) -> void:
	_phase = p
	_time_left = seconds
	_picker.visible = false
	if p == Rules.MeetingPhase.VOTE:
		_subtitle.text = "Vote now. The most votes is banished; a tie or skip banishes nobody."
		LGAudio.play_sfx("res://assets/kenney/audio/sfx/bong_001.ogg", -4.0)
	_update_controls()


func _vote(target: int) -> void:
	if _voted or _phase != Rules.MeetingPhase.VOTE or not _can_act():
		return
	_voted = true
	game.to_host("_c_vote", [target])
	_update_controls()


func _on_result(res: Dictionary) -> void:
	_phase = Rules.MeetingPhase.REVEAL
	_time_left = 0.0
	var b: int = res.banished
	if b == Rules.SKIP_VOTE:
		_title.text = "Nobody was banished"
		_subtitle.text = "The votes were tied." if res.get("tie", false) else "Most chose to skip."
	else:
		_title.text = "%s was banished" % game.player_name(b)
		if res.has("role"):
			_subtitle.text = "%s %s Hollow." % [game.player_name(b), "WAS" if res.role == Rules.Role.HOLLOW else "was NOT"]
		else:
			_subtitle.text = "Their role stays a secret."
	if res.has("votes"):
		var parts := []
		for voter in res.votes:
			var t: int = res.votes[voter]
			parts.append("%s: %s" % [game.player_name(voter), "skip" if t == Rules.SKIP_VOTE else game.player_name(t)])
		_subtitle.text += "\nVotes: " + ", ".join(parts)
	LGAudio.play_sfx("res://assets/kenney/audio/sfx/impactBell_heavy_001.ogg", -2.0)
	_update_controls()
