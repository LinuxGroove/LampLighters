class_name HowToPanel
extends Control
## "How to play": a few parchment pages on the goal, a night, meetings, winning,
## roles and the controls. Opened from the title menu and the pause menu, and
## by itself at the start of a player's first game if they never opened it.

signal closed

var _title: Label
var _body: Label
var _extra: VBoxContainer
var _count: Label
var _prev: Button
var _next: Button
var _page := 0


static func pages() -> Array:
	var goal := int(round(float(Rules.DEFAULT_SETTINGS.dawn_chore_goal) * 100.0))
	var dark := int(round(float(Rules.DEFAULT_SETTINGS.dark_fraction) * 100.0))
	return [
		{"title": "The goal", "body":
			"Every night in Moonpatch Village the lanterns must stay lit until dawn.\n\nMost of you are Lamplighters. But one or two of you are secretly the Hollow, and they are putting the lanterns out and taking villagers in the dark.\n\nWork out who you can trust."},
		{"title": "A night in the village", "body":
			"Walk around the village with the left stick. You can only see as far as the light reaches, so stay near the lanterns.\n\nEvery Lamplighter has chores to finish, like pumping water or mending the fence. Each one is a short game at a station. Chores need a lit lantern nearby.\n\nWhen a lantern goes dark, hold the action button next to it to relight it."},
		{"title": "Bells and meetings", "body":
			"Found someone who was taken? Report them. Or ring the bell in the square. Either one calls a meeting and everyone gathers.\n\nTalk it over with quick chat, then vote in secret. The villager with the most votes is banished and is out of the village. Skipping is always allowed.\n\nBanished or taken players become ghosts. They can still finish chores."},
		{"title": "How to win", "body":
			"The village wins if every Hollow is banished, or if dawn comes and at least %d%% of the chores are done.\n\nThe Hollow win if they outnumber the village, if fewer than %d%% of the lanterns are left lit, or if dawn comes with too many chores undone." % [goal, dark]},
		{"title": "Roles", "body":
			"Lamplighter: do chores, keep the lanterns lit, find the Hollow.\n\nHollow: snuff lanterns and take villagers in the dark. Hide among everyone else.\n\nSeer (five or more players): look closely at one villager to learn if they are Hollow.\n\nWatchman (seven or more players): see fresh footprints in the dark.\n\nYou get a card with your role and goals when each game starts."},
		{"title": "Controls", "body": "", "controls": true},
	]


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
	panel.custom_minimum_size = Vector2(760, 520)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title = LGUi.label("", "InkTitle")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_body = LGUi.label("", "InkLabel")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = 700
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_extra = VBoxContainer.new()
	_extra.add_theme_constant_override("separation", 6)
	_extra.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_extra)
	_count = LGUi.label("", "InkLabel")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_count)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	_prev = LGUi.button("Previous", func(): _go(-1), 200)
	row.add_child(_prev)
	_next = LGUi.button("Next", func(): _go(1), 200)
	row.add_child(_next)


func open() -> void:
	LGSettings.set_value("tutorial", "howto_seen", true)
	_page = 0
	visible = true
	_show_page()
	_next.grab_focus.call_deferred()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _go(dir: int) -> void:
	_page += dir
	if _page >= pages().size():
		close()
		return
	_page = maxi(_page, 0)
	_show_page()
	(_prev if dir < 0 and _prev.visible else _next).grab_focus.call_deferred()


func _show_page() -> void:
	var all := pages()
	var page: Dictionary = all[_page]
	_title.text = page.title
	_body.text = page.body
	_body.visible = page.body != ""
	for c in _extra.get_children():
		_extra.remove_child(c)
		c.queue_free()
	_extra.visible = page.get("controls", false)
	if _extra.visible:
		_build_controls()
	_count.text = "%d / %d" % [_page + 1, all.size()]
	_prev.visible = _page > 0
	_next.text = "Done" if _page == all.size() - 1 else "Next"


func _build_controls() -> void:
	for pair in [["move_up", "Walk around"], ["interact", "Relight, do a chore, report"],
			["special", "Your role's special action"], ["ring_bell", "Ring the bell (in the square)"],
			["show_map", "Open the map"], ["pause", "Pause"]]:
		var holder := PanelContainer.new()
		holder.theme_type_variation = "GlassPanel"
		holder.add_child(ActionPrompt.make(pair[0], pair[1], 32))
		_extra.add_child(holder)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		close()
