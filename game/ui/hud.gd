class_name Hud
extends CanvasLayer
## The in-match overlay: dawn timer, chore and lantern progress, the role
## card, button prompts, toasts, and the chore, meeting, map, pause and end
## screens.

var game: Game
var root: Control
var chore_game: ChoreGame
var meeting: MeetingPanel
var map: MapPanel
var pause: PauseMenu
var end: EndPanel
var howto: HowToPanel
var role_card: RoleCard
var guide: PracticeGuide
var hints: Hints
var practice := false

var _top: PanelContainer
var _time_label: Label
var _chore_bar: ProgressBar
var _lantern_label: Label
var _role_panel: PanelContainer
var _role_label: Label
var _role_hint: Label
var _chores_panel: PanelContainer
var _chore_list: VBoxContainer
var _prompts: VBoxContainer
var _prompt_a: ActionPrompt
var _prompt_x: ActionPrompt
var _prompt_y: ActionPrompt
var _hold_bar: ProgressBar
var _toast: Label
var _toast_t := 0.0
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _banner_t := 0.0
var _waiting: Label
var _hint: PanelContainer
var _hint_row: HBoxContainer
var _hint_t := 0.0


func setup(p_game: Game) -> void:
	game = p_game
	practice = bool(game.config.get("practice", false))
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_vignette()
	_build_top()
	_build_role()
	_build_chores()
	_build_prompts()
	_build_toast_and_banner()
	_waiting = LGUi.label("Waiting for everyone to reach the village...", "HeaderMedium")
	_waiting.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_waiting.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_waiting)
	chore_game = ChoreGame.new()
	root.add_child(chore_game)
	map = MapPanel.new()
	root.add_child(map)
	map.setup(game)
	meeting = MeetingPanel.new()
	root.add_child(meeting)
	meeting.setup(game)
	end = EndPanel.new()
	root.add_child(end)
	end.setup(game)
	pause = PauseMenu.new()
	root.add_child(pause)
	pause.setup(game)
	howto = HowToPanel.new()
	root.add_child(howto)
	role_card = RoleCard.new()
	root.add_child(role_card)
	_build_hint()
	if practice:
		_time_label.visible = false
		_toast.position.y = 170
		guide = PracticeGuide.new()
		add_child(guide)
		guide.setup(game, self)
	else:
		hints = Hints.new()
		add_child(hints)
		hints.setup(game, self)
	_set_playing_visible(false)
	game.intro_received.connect(_on_intro)
	game.private_changed.connect(_refresh_chores)
	game.status_changed.connect(_refresh_top)
	game.lanterns_changed.connect(_refresh_top)
	game.toast.connect(show_toast)
	game.meeting_started.connect(func(_i): _set_playing_visible(false); map.close(); chore_game.close())
	game.meeting_ended.connect(func(): _set_playing_visible(true))
	game.game_over.connect(func(_r): _set_playing_visible(false); map.close(); pause.close(); chore_game.close())


func blocks_input() -> bool:
	return chore_game.visible or meeting.visible or map.visible or pause.visible or end.visible \
			or howto.visible or role_card.visible or (guide != null and guide.blocking())


func open_chore(chore: Dictionary, on_done: Callable) -> void:
	chore_game.open(chore, on_done)


func close_chore() -> void:
	chore_game.close()


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_t = 3.0


## A one-time tip near the top of the screen, with the button glyph if `action` is set.
func show_hint(text: String, action := "", seconds := 9.0) -> void:
	for c in _hint_row.get_children():
		_hint_row.remove_child(c)
		c.queue_free()
	if action != "":
		_hint_row.add_child(ActionPrompt.make(action, text, 36))
	else:
		_hint_row.add_child(LGUi.label(text))
	_hint.visible = true
	_hint_t = seconds


func show_banner(title: String, text: String, seconds := 6.0) -> void:
	_banner_title.text = title
	_banner_text.text = text
	_banner.visible = true
	_banner_t = seconds


func _process(delta: float) -> void:
	if game.player:
		game.player.locked = blocks_input()
	if game.phase == Rules.Phase.NIGHT:
		game.night_left = maxf(0.0, game.night_left - delta)
		_time_label.text = "Dawn in %d:%02d" % [int(game.night_left) / 60, int(game.night_left) % 60]
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0 or blocks_input():
			_hint.visible = false
			_hint_t = 0.0
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			_banner.visible = false
	_update_prompts()


func _unhandled_input(event: InputEvent) -> void:
	if end.visible or game.phase == Rules.Phase.LOADING:
		return
	if howto.visible or role_card.visible or (guide != null and guide.blocking()):
		return
	if pause.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("cancel"):
			get_viewport().set_input_as_handled()
			pause.close()
		return
	if map.visible:
		if event.is_action_pressed("show_map") or event.is_action_pressed("cancel"):
			get_viewport().set_input_as_handled()
			map.close()
		return
	if chore_game.visible:
		return
	if _banner.visible and event.is_action_pressed("interact") and not meeting.visible:
		get_viewport().set_input_as_handled()
		_banner.visible = false
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause.open()
	elif event.is_action_pressed("show_map") and game.phase == Rules.Phase.NIGHT:
		get_viewport().set_input_as_handled()
		map.open()


func _on_intro() -> void:
	_waiting.visible = false
	_set_playing_visible(true)
	var role: int = game.role
	_role_label.text = Rules.ROLE_NAMES[role]
	_role_label.modulate = Color("ff6a5f") if role == Rules.Role.HOLLOW else Color("ffd27a")
	var hint: String = Rules.ROLE_BLURBS[role]
	if role == Rules.Role.HOLLOW and not game.allies.is_empty():
		var names := []
		for a in game.allies:
			names.append(game.player_name(a))
		hint += "\nYour fellow Hollow: %s." % ", ".join(names)
	_role_hint.text = hint
	if practice:
		show_banner("Practice round", "There is no Hollow and no clock here. Follow the guide at the top of the screen.", 8.0)
	elif bool(LGSettings.get_value("tutorial", "role_card", true)):
		show_role_card()
	else:
		show_banner("You are %s %s" % ["the" if role != Rules.Role.LAMPLIGHTER else "a", Rules.ROLE_NAMES[role]], hint, 7.0)
	_refresh_top()
	_refresh_chores()


func show_role_card() -> void:
	var names := []
	for a in game.allies:
		names.append(game.player_name(a))
	role_card.show_role(game.role, names)


func _set_playing_visible(on: bool) -> void:
	for c in [_top, _role_panel, _chores_panel, _prompts]:
		c.visible = on and game.phase != Rules.Phase.LOADING


# --- Building ---------------------------------------------------------------

func _build_vignette() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.75))
	grad.add_point(0.55, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)


func _build_top() -> void:
	_top = PanelContainer.new()
	_top.theme_type_variation = "GlassPanel"
	_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top.position.y = 12
	root.add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_top.add_child(row)
	_time_label = LGUi.label("Dawn in 8:00")
	_time_label.custom_minimum_size.x = 150
	_time_label.theme_type_variation = "HintLabel"
	row.add_child(_time_label)
	var chores := VBoxContainer.new()
	chores.add_theme_constant_override("separation", 0)
	row.add_child(chores)
	var cl := LGUi.label("Village chores", "HintLabel")
	chores.add_child(cl)
	_chore_bar = ProgressBar.new()
	_chore_bar.theme_type_variation = "BlueProgressBar"
	_chore_bar.custom_minimum_size = Vector2(180, 20)
	_chore_bar.show_percentage = false
	_chore_bar.max_value = 1.0
	chores.add_child(_chore_bar)
	_lantern_label = LGUi.label("Lanterns 16/16", "HintLabel")
	row.add_child(_lantern_label)


func _build_role() -> void:
	_role_panel = PanelContainer.new()
	_role_panel.theme_type_variation = "GlassPanel"
	_role_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_role_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_role_panel.offset_left = 16
	_role_panel.offset_bottom = -16
	_role_panel.custom_minimum_size.x = 300
	root.add_child(_role_panel)
	var col := VBoxContainer.new()
	_role_panel.add_child(col)
	_role_label = LGUi.label("", "HeaderMedium")
	col.add_child(_role_label)
	_role_hint = LGUi.label("", "HintLabel")
	_role_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_role_hint.custom_minimum_size.x = 300
	_role_hint.visible = false
	col.add_child(_role_hint)


func _build_chores() -> void:
	_chores_panel = PanelContainer.new()
	_chores_panel.theme_type_variation = "GlassPanel"
	_chores_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_chores_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chores_panel.offset_right = -16
	_chores_panel.offset_top = 12
	_chores_panel.custom_minimum_size.x = 250
	root.add_child(_chores_panel)
	_chore_list = VBoxContainer.new()
	_chores_panel.add_child(_chore_list)


func _build_prompts() -> void:
	_prompts = VBoxContainer.new()
	_prompts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompts.position.y = -24
	_prompts.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(_prompts)
	_hold_bar = ProgressBar.new()
	_hold_bar.custom_minimum_size = Vector2(260, 20)
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.visible = false
	_prompts.add_child(_hold_bar)
	for p in [["interact", "a"], ["special", "x"], ["ring_bell", "y"]]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = "GlassPanel"
		var prompt := ActionPrompt.make(p[0], "", 36)
		panel.add_child(prompt)
		_prompts.add_child(panel)
		match p[1]:
			"a":
				_prompt_a = prompt
			"x":
				_prompt_x = prompt
			"y":
				_prompt_y = prompt


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.theme_type_variation = "GlassPanel"
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y = 150 if not practice else 230
	_hint.visible = false
	root.add_child(_hint)
	_hint_row = HBoxContainer.new()
	_hint.add_child(_hint_row)


func _build_toast_and_banner() -> void:
	_toast = LGUi.label("", "HeaderMedium")
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 90
	_toast.visible = false
	root.add_child(_toast)
	_banner = PanelContainer.new()
	_banner.theme_type_variation = "ParchmentPanel"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.custom_minimum_size = Vector2(560, 0)
	_banner.visible = false
	root.add_child(_banner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_banner.add_child(col)
	_banner_title = LGUi.label("", "InkTitle")
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_title)
	_banner_text = LGUi.label("", "InkLabel")
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.custom_minimum_size.x = 500
	col.add_child(_banner_text)


# --- Refreshing --------------------------------------------------------------

func _refresh_top() -> void:
	_chore_bar.value = 0.0 if game.chores_total <= 0 else float(game.chores_done) / float(game.chores_total)
	var on: int = game.lit.count(true)
	var needed := int(ceil(game.lit.size() * float(game.settings.get("dark_fraction", 0.25))))
	_lantern_label.text = "Lanterns %d/%d" % [on, game.lit.size()]
	_lantern_label.modulate = Color("ff8a7a") if on <= needed + 2 else Color.WHITE


func _refresh_chores() -> void:
	for c in _chore_list.get_children():
		c.queue_free()
	var title := "Chores"
	if game.role == Rules.Role.HOLLOW:
		title = "Chores (pretend)"
	elif game.is_ghost():
		title = "Chores (as a ghost)"
	_chore_list.add_child(LGUi.label(title, "HeaderMedium"))
	for c in game.you.get("chores", []):
		var chore: Dictionary = Rules.CHORES[c[0]]
		var text: String = chore.label
		if chore.steps.size() > 1 and not c[2]:
			text += " (%d/%d)" % [c[1] + 1, chore.steps.size()]
		var l := LGUi.label(("Done: " if c[2] else "") + text, "HintLabel")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 240
		if c[2]:
			l.modulate = Color(1, 1, 1, 0.55)
		_chore_list.add_child(l)


func _update_prompts() -> void:
	var p: LocalPlayer = game.player
	if p == null or game.phase != Rules.Phase.NIGHT or blocks_input():
		for x in [_prompt_a, _prompt_x, _prompt_y]:
			x.get_parent().visible = false
		_hold_bar.visible = false
		return
	_prompt_a.get_parent().visible = not p.interact.is_empty() and p.busy.is_empty()
	if not p.interact.is_empty():
		_prompt_a.text = p.interact.text
	_prompt_x.get_parent().visible = not p.special.is_empty() and p.busy.is_empty()
	if not p.special.is_empty():
		var cd := float(p.special.get("cd", 0.0))
		_prompt_x.text = p.special.text + ("  (%d s)" % ceili(cd) if cd > 0.0 else "")
		_prompt_x.modulate.a = 0.5 if cd > 0.0 else 1.0
	_prompt_y.get_parent().visible = p.can_ring and p.busy.is_empty()
	_prompt_y.text = "Ring the bell" + ("  (%d s)" % ceili(p.bell_cd) if p.bell_cd > 0.0 else "")
	var prog := p.relight_progress()
	_hold_bar.visible = prog >= 0.0
	_hold_bar.value = prog
