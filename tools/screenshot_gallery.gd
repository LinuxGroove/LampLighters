extends Node
## Saves a screenshot of every screen worth seeing, in groups: the menus and
## lobby, each place in the village, a night, each role, the chores, meetings,
## endings and the practice round. Run through tools/screenshot.tscn:
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --resolution 1280x800 tools/screenshot.tscn -- --all=docs/screenshots [group=meetings]
## Writes <dir>/<group>/<shot>.jpg, and <dir>/README.md listing them all when
## every group was made.
##
## Nights are staged on the host: the seed is fixed, the local player is dealt
## the role a shot needs, bots are placed by hand and stand still, and lanterns
## are put out where a shot needs the dark. Prompts show Xbox buttons, since
## the game is controller first. The player's settings file is put back after.
## Under xvfb, install mesa-vulkan-drivers so Godot renders with Vulkan (the
## game's Mobile renderer) instead of falling back to a paler OpenGL.

const GROUPS := [
	["menus", "Menus and the lobby"],
	["village", "Moonpatch Village"],
	["play", "A night"],
	["roles", "Roles"],
	["chores", "Chores"],
	["meetings", "Meetings"],
	["endings", "Endings"],
	["practice", "The practice round"],
]
const SEED := 4242
const SETTINGS_PATH := "user://settings.cfg"
## A spot west of the square, among the houses, that goes dark when the three
## lanterns around it are out.
const DARK_SPOT := Vector3(-16.0, 0.0, -4.5)
## Open grass west of the campfire, dark with two lanterns out.
const WATCH_SPOT := Vector3(-19.0, 0.0, 7.0)

var game: Game
var host: MatchHost

var _root := ""
var _shots: Array = []  # [group, file, caption]
var _want_role := -1
var _saved_settings := PackedByteArray()
var _had_settings := false
var _overview_cam: Camera3D


func run(dir: String, only: String) -> void:
	_root = dir if dir.begins_with("/") else ProjectSettings.globalize_path("res://").path_join(dir)
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)
	LGSettings.set_value("player", "name", "Ken", false)
	LGSettings.set_value("player", "look", 1, false)
	for key in ["welcomed", "howto_seen"]:
		LGSettings.set_value("tutorial", key, true, false)
	for key in ["role_card", "hints"]:
		LGSettings.set_value("tutorial", key, false, false)
	LGSettings.set_value("tutorial", "seen", "", false)
	LGInput.family = "xbox"
	LGInput.device_changed.emit("xbox")
	# Scene changes replace the current scene; this node stays to drive them.
	get_tree().current_scene = null
	get_tree().node_added.connect(_on_node_added)
	for g in GROUPS:
		if only != "" and g[0] != only:
			continue
		match g[0]:
			"menus":
				await _menus()
			"village":
				await _village()
			"play":
				await _play()
			"roles":
				await _roles()
			"chores":
				await _chores()
			"meetings":
				await _meetings()
			"endings":
				await _endings()
			"practice":
				await _practice()
	Engine.time_scale = 1.0
	if only == "":
		_write_index()
	_restore_settings()
	get_tree().quit()


# --- Groups ------------------------------------------------------------------

func _menus() -> void:
	# The first run: no name yet.
	LGSettings.set_value("player", "name", "", false)
	var t: Node = await _title()
	await _shot("menus", "first-name", "Choosing a name on the first run")
	var edit: LineEdit = t._col.find_children("*", "LineEdit", true, false)[0]
	var kb := OnScreenKeyboard.open(edit, false)
	for ch in "Ken":
		kb._type(ch)
	await _wait(0.4)
	await _shot("menus", "keyboard", "The on-screen keyboard, for typing with a controller")
	kb._close()
	LGSettings.set_value("player", "name", "Ken", false)
	t._show_welcome()
	await _wait(0.4)
	await _shot("menus", "welcome", "The welcome, offering the tutorial and the practice round")
	t._show_main()
	await _wait(0.4)
	await _shot("menus", "title", "The title menu")
	t._show_howto_menu()
	await _wait(0.4)
	await _shot("menus", "how-to-play", "How to play")
	t._show_tutorial()
	await _wait(0.4)
	var panel: HowToPanel = t._ui.get_child(t._ui.get_child_count() - 1)
	var pages := HowToPanel.pages()
	for i in pages.size():
		await _shot("menus", "tutorial-%d" % (i + 1), "Tutorial page %d: %s" % [i + 1, pages[i].title])
		if i < pages.size() - 1:
			panel._go(1)
			await _wait(0.3)
	# The controls page again, with keyboard keys.
	_use_pad(false)
	panel._show_page()
	await _wait(0.3)
	await _shot("menus", "tutorial-%d-keyboard" % pages.size(), "Tutorial page %d: %s, on a keyboard" % [pages.size(), pages[pages.size() - 1].title])
	_use_pad(true)
	panel.close()
	await _wait(0.2)
	t._show_settings()
	await _wait(0.4)
	await _shot("menus", "settings", "Settings")
	t._show_about()
	await _wait(0.4)
	await _shot("menus", "about", "About Graveyard Hollow")
	t._show_local()
	await _wait(0.4)
	await _shot("menus", "local-network", "Local network play")
	t._show_join()
	await _wait(0.6)
	await _shot("menus", "join", "Joining a game on the same network")
	Session.stop_browsing()
	t._show_online()
	await _wait(0.4)
	await _shot("menus", "online", "Play online")
	# The lobby for a game with bots.
	Session.start_solo(5)
	var lobby: Node = await _scene("res://game/ui/lobby.tscn")
	await _wait(1.5)
	await _shot("menus", "lobby", "The lobby for a game with bots: players, house rules and your look")
	var c: LGCycler = lobby._cyclers["night_minutes"]
	c.grab_focus()
	c.set_editing(true)
	await _wait(0.3)
	await _shot("menus", "lobby-setting", "Changing a house rule")
	c.set_editing(false)
	# Hosting on the local network shows the join code.
	Session.leave()
	if Session.host_lan():
		await _scene("res://game/ui/lobby.tscn")
		await _wait(1.5)
		await _shot("menus", "lobby-lan", "Hosting on the local network, with the join code at the top")
	Session.leave()
	await _title()


func _village() -> void:
	await _night(Rules.Role.LAMPLIGHTER)
	await _overview()
	await _shot("village", "overview", "Moonpatch Village from above, every lantern lit")
	# Brighter, to show the layout.
	var env: Environment = game.village.get_node("Night").environment
	var moon: DirectionalLight3D = game.village.get_node("Moon")
	var was := [env.ambient_light_energy, moon.light_energy]
	env.ambient_light_energy = 0.9
	moon.light_energy = 0.9
	await _wait(0.3)
	await _shot("village", "overview-bright", "Moonpatch Village from above, brightened to show the layout")
	env.ambient_light_energy = was[0]
	moon.light_energy = was[1]
	_end_overview()
	var marks := game.village.landmark_positions()
	for place in marks:
		await _put(game.my_id, _spot_near(marks[place], 1.2))
		await _wait(0.5)
		var file := str(place).trim_prefix("the ").replace(" ", "-")
		await _shot("village", file, _sentence(str(place)))
	# Every other lantern out, to compare lit and dark streets.
	await _put(game.my_id, _spot_near(Vector3(0, 0, 0.5), 1.0))
	for i in host.lit.size():
		host.lit[i] = i % 2 == 0
	host._send_lanterns()
	await _wait(0.6)
	await _shot("village", "square-dark", "The square with every other lantern out")


func _play() -> void:
	await _night(Rules.Role.LAMPLIGHTER)
	# Bots set off to their chores for a few seconds.
	await _put(game.my_id, _spot_near(Vector3(0, 0, 4.5), 1.0))
	host.practice = false
	await _wait(9.0)
	host.practice = true
	await _wait(0.5)
	await _shot("play", "night", "A night begins: the clock, the village's chores and lanterns at the top, your chores on the right")
	var views := game.visible_views()
	for i in mini(views.size(), 3):
		game._h_emote(views[i].actor_id, 1 + i)
	game._h_emote(game.my_id, 3)
	await _wait(0.4)
	await _shot("play", "emotes", "Emotes on the d-pad")
	game.hud.map.open()
	await _wait(0.4)
	await _shot("play", "map", "The map: lanterns, your chores, and where you are")
	game.hud.map.close()
	game.hud.pause.open()
	game.hud.pause._help.visible = true
	await _wait(0.4)
	await _shot("play", "pause", "The pause menu, with the controls shown")
	game.hud.pause.close()
	# A one-time tip, the first time a lantern goes dark.
	LGSettings.set_value("tutorial", "hints", true, false)
	var near := _nearest_lantern(game.player.global_position)
	await _put(game.my_id, _spot_near(host.lantern_pos[near], 2.0))
	host._set_lit(near, false)
	await _wait(1.2)
	await _shot("play", "tip", "A one-time tip, the first time a lantern goes dark")
	LGSettings.set_value("tutorial", "hints", false, false)
	game.hud._hint.visible = false


func _roles() -> void:
	# The Lamplighter.
	await _night(Rules.Role.LAMPLIGHTER)
	await _card("lamplighter", "The Lamplighter's card")
	var lantern := 0
	host._set_lit(lantern, false)
	await _put(game.my_id, _spot_near(host.lantern_pos[lantern], 1.4))
	await _wait(0.6)
	await _shot("roles", "lamplighter-relight", "Lamplighter: next to a dark lantern")
	Input.action_press("interact")
	game.player._do_interact()
	await _wait(1.0)
	await _shot("roles", "lamplighter-relighting", "Lamplighter: holding to relight it")
	Input.action_release("interact")
	await _wait(0.2)

	# The Hollow, with a fellow Hollow.
	await _night(Rules.Role.HOLLOW)
	await _card("hollow", "The Hollow's card, naming the other Hollow")
	var me: Dictionary = host.actors[game.my_id]
	me.snuff_ready = 0.0
	me.take_ready = 0.0
	host._send_private(game.my_id)
	var ally: int = _bots_with(Rules.Role.HOLLOW)[0]
	lantern = 7
	await _put(game.my_id, _spot_near(host.lantern_pos[lantern], 1.4))
	await _put(ally, game.player.global_position + Vector3(-2.2, 0, 0.6), game.player.global_position)
	await _wait(0.7)
	await _shot("roles", "hollow-snuff", "Hollow: next to a lit lantern, with the other Hollow marked in red")
	game.player._do_special()
	await _wait(0.5)
	await _put(game.my_id, _spot_near(host.lantern_pos[8], 1.4))
	await _wait(0.6)
	await _shot("roles", "hollow-cooldown", "Hollow: the next snuff waits for its cooldown")
	_lanterns_off(DARK_SPOT, 9.0)
	var victim: int = _bots_with(Rules.Role.LAMPLIGHTER)[0]
	await _put(game.my_id, _spot_near(DARK_SPOT, 0.0))
	await _put(victim, game.player.global_position + Vector3(1.3, 0, 0.3), game.player.global_position)
	await _wait(0.7)
	await _shot("roles", "hollow-take", "Hollow: a villager alone in the dark")
	game.player._do_special()
	await _wait(0.7)
	await _shot("roles", "hollow-taken", "Hollow: what's left after a take, for someone to find")

	# The Seer, next to a Hollow.
	await _night(Rules.Role.SEER)
	await _card("seer", "The Seer's card")
	var hollow: int = _bots_with(Rules.Role.HOLLOW)[0]
	await _put(game.my_id, _spot_near(Vector3(12.0, 0, 6.0), 0.0))
	await _put(hollow, game.player.global_position + Vector3(1.6, 0, 0.2), game.player.global_position)
	await _wait(0.7)
	await _shot("roles", "seer-look", "Seer: next to a villager, ready to look closely")
	game.player._do_special()
	await _wait(0.8)
	await _shot("roles", "seer-result", "Seer: what the look showed")

	# The Watchman, as someone hurries past in the dark.
	await _night(Rules.Role.WATCHMAN)
	await _card("watchman", "The Watchman's card")
	_lanterns_off(WATCH_SPOT, 9.0)
	await _put(game.my_id, _spot_near(WATCH_SPOT, 0.0))
	var walker: int = _bots()[2]
	var path := game.village.find_path(_spot_near(WATCH_SPOT + Vector3(-7.0, 0, 3.5), 0.0),
		_spot_near(WATCH_SPOT + Vector3(6.5, 0, -4.0), 0.0))
	await _put(walker, path[0], path[mini(1, path.size() - 1)])
	var a: Dictionary = host.actors[walker]
	for i in range(1, path.size()):
		var from: Vector3 = path[i - 1]
		var to: Vector3 = path[i]
		var n := maxi(1, ceili(from.distance_to(to) / 0.25))
		a.yaw = atan2(to.x - from.x, to.z - from.z)
		for k in n:
			a.pos = from.lerp(to, float(k + 1) / n)
			a.anim = Rules.Anim.WALK
			await get_tree().process_frame
	a.anim = Rules.Anim.IDLE
	await _wait(0.4)
	await _shot("roles", "watchman-footprints", "Watchman: fresh footprints show where someone just walked")

	# A ghost: taken in the dark.
	await _night(Rules.Role.LAMPLIGHTER)
	_lanterns_off(DARK_SPOT, 9.0)
	await _put(game.my_id, _spot_near(DARK_SPOT, 0.0))
	hollow = _bots_with(Rules.Role.HOLLOW)[0]
	await _put(hollow, game.player.global_position + Vector3(1.3, 0, 0.3), game.player.global_position)
	await _wait(0.6)
	host._take(host.actors[hollow], host.actors[game.my_id])
	await _wait(1.0)
	await _shot("roles", "ghost-taken", "Taken: you're a ghost now, and you learn who took you")
	game.hud._banner.visible = false
	lantern = 2
	await _put(game.my_id, _spot_near(host.lantern_pos[lantern], 2.0))
	await _wait(0.8)
	await _shot("roles", "ghost-flicker", "Ghost: still doing chores, and next to a lantern to flicker as a hint")
	game.player._do_special()
	await _wait(0.6)
	await _shot("roles", "ghost-flickering", "Ghost: the lantern flickers for everyone nearby")


func _chores() -> void:
	await _night(Rules.Role.LAMPLIGHTER, 10, {"chores_each": Rules.CHORES.size()})
	var stations := game.village.stations()
	var fountain: Vector3 = stations["fountain"].global_position
	await _put(game.my_id, _spot_near(fountain, 1.7))
	await _wait(0.6)
	await _shot("chores", "station", "Your chore stations glow; walk up to one to start")
	for key in ["water", "fence", "animals", "candles", "hay", "wood", "market", "grave"]:
		var step: Dictionary = Rules.CHORES[key].steps[0]
		await _put(game.my_id, _spot_near(stations[step.station].global_position, 1.6))
		await _wait(0.5)
		if game.player.interact.get("kind", "") != "chore":
			push_warning("No chore prompt at %s" % step.station)
			continue
		game.player._do_interact()
		await _wait(0.4)
		var cg := game.hud.chore_game
		match cg.kind:
			"hold":
				cg.progress = 0.45
			"mash":
				cg.progress = 0.6
			"timing":
				cg._hits = 1
				cg.progress = 1.0 / ChoreGame.HITS_NEEDED
			"sequence":
				cg._seq_i = 1
				cg.progress = 1.0 / cg._seq.size()
				cg._show_sequence()
		await _wait(0.3)
		var game_names := {"hold": "hold", "mash": "tap quickly", "timing": "tap in the green zone", "sequence": "press the directions in order"}
		await _shot("chores", key, "%s (%s)" % [Rules.CHORES[key].label, game_names[cg.kind]])
		if key == "wood":
			# Finish the first step to carry the wood over.
			await _wait(1.2)
			cg.progress = 1.0
			await _wait(0.5)
			await _put(game.my_id, _spot_near(stations["campfire"].global_position, 1.6))
			await _wait(0.6)
			await _shot("chores", "wood-carry", "Carrying the wood to the campfire, the second step")
		else:
			game.hud.close_chore()
			await _wait(0.3)
	# Too dark to work.
	var market: Vector3 = stations["market"].global_position
	_lanterns_off(market, Rules.WORK_LIGHT_RADIUS + 0.5)
	await _put(game.my_id, _spot_near(market, 1.6))
	await _wait(0.6)
	await _shot("chores", "too-dark", "A station with no lit lantern nearby is too dark to work at")


func _meetings() -> void:
	await _night(Rules.Role.LAMPLIGHTER, 10, {"discussion_seconds": 20, "vote_seconds": 20})
	# Someone is taken in the dark, and another villager sees it happen.
	var hollow: int = _bots_with(Rules.Role.HOLLOW)[0]
	var villagers := _bots_with(Rules.Role.LAMPLIGHTER)
	var victim: int = villagers[0]
	var witness: int = villagers[1]
	_lanterns_off(DARK_SPOT, 9.0)
	var spot := _spot_near(DARK_SPOT, 0.0)
	await _put(victim, spot)
	await _put(hollow, spot + Vector3(1.2, 0, 0.0), spot)
	await _put(witness, spot + Vector3(-3.0, 0, 1.0), spot)
	await _wait(0.3)
	host._take(host.actors[hollow], host.actors[victim])
	await _put(hollow, _spot_near(Vector3(3.0, 0, -2.0), 0.0))
	await _put(witness, spot + Vector3(-5.0, 0, -2.0), spot)
	await _put(game.my_id, spot + Vector3(0.4, 0, 1.6))
	await _wait(0.8)
	await _shot("meetings", "found", "Finding a villager's dropped lantern in the dark")
	game.player._do_interact()
	await _talk(12.0)
	await _shot("meetings", "report", "A meeting called by a report: bots say what they saw")
	var mp := game.hud.meeting
	mp._chat.get_child(0).pressed.emit()
	await _wait(0.4)
	await _shot("meetings", "quick-chat", "Quick chat: choosing who you suspect")
	_press_picker(game.player_name(hollow))
	await _wait(0.3)
	mp._chat.get_child(3).pressed.emit()
	await _wait(0.2)
	_press_picker(game.player_name(hollow))
	await _wait(0.4)
	await _shot("meetings", "quick-chat-place", "Quick chat: choosing where you saw them")
	_press_picker(host.village.landmark_name(spot).capitalize())
	await _wait(1.0)
	await _to_vote()
	await _shot("meetings", "vote", "Voting, in secret")
	mp._vote(hollow)
	await _talk(5.0)
	await _shot("meetings", "voted", "Vote sent, waiting for the others")
	await _reveal({hollow: 7, Rules.SKIP_VOTE: 2})
	await _shot("meetings", "banished-hollow", "Banished, and they were Hollow")
	await _end_meeting()

	# The bell.
	host.actors[game.my_id].bell_ready = 0.0
	host._send_private(game.my_id)
	await _put(game.my_id, _spot_near(game.village.bell_position(), 1.5))
	await _wait(0.6)
	await _shot("meetings", "bell-ring", "At the bell in the square, ready to call a meeting")
	game.act(Rules.Act.BELL)
	await _talk(14.0)
	await _shot("meetings", "bell", "A meeting called by the bell")
	await _to_vote()
	await _reveal({villagers[2]: 5, villagers[3]: 2, Rules.SKIP_VOTE: 1})
	await _shot("meetings", "banished-villager", "Banished, and they were not Hollow")
	await _end_meeting()

	var caller: int = villagers[3]
	host._start_meeting(caller, "bell", {})
	await _talk(5.0)
	await _to_vote()
	await _reveal({villagers[1]: 3, villagers[4]: 3, Rules.SKIP_VOTE: 1})
	await _shot("meetings", "tie", "A tie: nobody is banished")
	await _end_meeting()

	host._start_meeting(caller, "bell", {})
	await _talk(5.0)
	await _to_vote()
	await _reveal({Rules.SKIP_VOTE: 5, villagers[4]: 2})
	await _shot("meetings", "skipped", "Most chose to skip")
	await _end_meeting()

	host.settings.anonymous_votes = false
	host._start_meeting(caller, "bell", {})
	await _talk(5.0)
	await _to_vote()
	await _reveal({villagers[4]: 4, villagers[1]: 1, Rules.SKIP_VOTE: 1})
	await _shot("meetings", "open-votes", "With secret votes off, everyone sees who voted for whom")
	await _end_meeting()

	host.settings.anonymous_votes = true
	host.settings.reveal_on_banish = false
	host._start_meeting(caller, "bell", {})
	await _talk(5.0)
	await _to_vote()
	await _reveal({villagers[1]: 3, Rules.SKIP_VOTE: 1})
	await _shot("meetings", "secret-role", "With role reveal off, a banished villager's role stays secret")
	await _end_meeting()

	# A ghost's view.
	await _night(Rules.Role.LAMPLIGHTER)
	_lanterns_off(DARK_SPOT, 9.0)
	await _put(game.my_id, _spot_near(DARK_SPOT, 0.0))
	hollow = _bots_with(Rules.Role.HOLLOW)[0]
	host._take(host.actors[hollow], host.actors[game.my_id])
	await _wait(0.5)
	host._start_meeting(_bots_with(Rules.Role.LAMPLIGHTER)[1], "bell", {})
	await _talk(6.0)
	await _shot("meetings", "ghost", "A meeting seen by a ghost, who can't speak or vote")


func _endings() -> void:
	var cases := [
		["village-found", Rules.Role.LAMPLIGHTER, Rules.Team.VILLAGE, "Every Hollow was found.", "The village wins: every Hollow was found"],
		["village-dawn", Rules.Role.SEER, Rules.Team.VILLAGE, "Dawn broke over a busy village.", "The village wins at dawn with enough chores done"],
		["hollow-outnumber", Rules.Role.HOLLOW, Rules.Team.HOLLOW, "The Hollow outnumber the village.", "The Hollow win, seen by a Hollow: they outnumber the village"],
		["hollow-dark", Rules.Role.WATCHMAN, Rules.Team.HOLLOW, "The village fell dark.", "The Hollow win: the village fell dark"],
		["hollow-dawn", Rules.Role.LAMPLIGHTER, Rules.Team.HOLLOW, "Dawn came with too many chores undone.", "The Hollow win at dawn with too many chores undone"],
	]
	for c in cases:
		await _night(c[1])
		var hollows := []
		var villagers := []
		for a in host.actors.values():
			if a.role == Rules.Role.HOLLOW:
				hollows.append(a)
			elif a.id != game.my_id:
				villagers.append(a)
		match c[0]:
			"village-found":
				for h in hollows:
					_banish(h)
				_take_some(hollows[0], villagers, 2)
				host.chores_done = host.chores_total / 2
			"village-dawn":
				_take_some(hollows[0], villagers, 3)
				host.chores_done = ceili(host.chores_total * 0.8)
				host.night_left = 0.0
			"hollow-outnumber":
				_banish(villagers[0])
				_take_some(hollows[1] if hollows[1].id != game.my_id else hollows[0], villagers.slice(1), 5)
				host.chores_done = host.chores_total / 3
			"hollow-dark":
				for i in host.lit.size():
					host.lit[i] = i % 5 == 0
				host._send_lanterns()
				_take_some(hollows[0], villagers, 2)
				host.chores_done = host.chores_total / 2
			"hollow-dawn":
				_banish(villagers[0])
				_take_some(hollows[0], villagers.slice(1), 2)
				host.chores_done = host.chores_total / 2
				host.night_left = 0.0
		await _wait(0.4)
		host._end(c[2], c[3])
		await _wait(1.0)
		await _shot("endings", c[0], c[4])


func _practice() -> void:
	await _night(Rules.Role.LAMPLIGHTER, 4, {}, true)
	var guide: PracticeGuide = game.hud.guide
	await _wait(1.5)
	await _shot("practice", "walk", "The practice round starts: walk around")
	game.hud._banner.visible = false
	game.hud._banner_t = 0.0
	# Walking far enough moves the guide on to the dark lantern.
	var dark := host.lit.find(false)
	var lantern_at := host.lantern_pos[dark]
	await _put(game.my_id, _spot_near(lantern_at + Vector3(0, 0, 9.0), 0.0))
	await _wait(0.8)
	await _shot("practice", "relight", "Practice: the guide points at a dark lantern")
	host._set_lit(dark, true)
	await _wait(0.8)
	await _shot("practice", "chores", "Practice: the guide points at your next chore and says how its game works")
	for i in PracticeGuide.CHORES_NEEDED:
		host._advance_chore(host.actors[game.my_id], i)
	await _wait(0.8)
	await _shot("practice", "map", "Practice: open the map")
	game.hud.map.open()
	await _wait(0.4)
	game.hud.map.close()
	await _put(game.my_id, _spot_near(game.village.bell_position() + Vector3(0, 0, 9.0), 0.0))
	await _wait(0.8)
	await _shot("practice", "bell", "Practice: ring the bell to call a meeting")
	await _put(game.my_id, _spot_near(game.village.bell_position(), 1.5))
	await _wait(0.3)
	game.act(Rules.Act.BELL)
	await _talk(6.0)
	await _shot("practice", "meeting", "Practice: talk with quick chat, then vote")
	await _to_vote()
	await _reveal({Rules.SKIP_VOTE: 4})
	await _end_meeting()
	await _wait(1.0)
	await _shot("practice", "done", "The end of the practice round")
	guide.queue_free()


# --- Nights --------------------------------------------------------------------

## Starts a solo night of `players` with this device dealt `role`, then
## freezes the bots and the clock (except in practice, where they already are).
func _night(role: int, players := 10, extra := {}, practice := false) -> void:
	if Session.mode != Session.Mode.SOLO:
		Session.start_solo(0)
	Engine.time_scale = 1.0
	Session.in_match = false
	Session.practice = practice
	Session.players = {1: Session._me()}
	for i in players - 1:
		Session.add_bot()
	var s := Rules.DEFAULT_SETTINGS.duplicate()
	s.ai_brains = false
	s.merge(extra, true)
	Session.settings = s
	_want_role = -1 if practice else role
	Session.start_match()
	game = await _settled()
	host = game.host
	while game.player == null:
		await get_tree().process_frame
	if not practice:
		host.practice = true
		for id in host.bots:
			host.actors[id].anim = Rules.Anim.IDLE
	await _wait(0.3)
	if not practice:
		# The "You are..." banner that stands in for the role card.
		game.hud._banner.visible = false
		game.hud._banner_t = 0.0


## Gives the game a fixed seed and, once the host has dealt, swaps this
## device's role with whoever got the one wanted.
func _on_node_added(node: Node) -> void:
	if node is Game:
		node.config["seed"] = SEED
		node.ready.connect(_deal.bind(node), CONNECT_ONE_SHOT)


func _deal(g: Game) -> void:
	if _want_role < 0 or g.host == null:
		return
	var me: Dictionary = g.host.actors[g.my_id]
	if me.role == _want_role:
		return
	for a in g.host.actors.values():
		if a.role == _want_role:
			a.role = me.role
			me.role = _want_role
			return
	push_error("Nobody was dealt %s" % Rules.ROLE_NAMES[_want_role])


func _card(role_name: String, caption: String) -> void:
	game.hud.show_role_card()
	await _wait(0.5)
	await _shot("roles", role_name + "-card", caption)
	game.hud.role_card.close()
	await _wait(0.2)


## Bot ids, in order.
func _bots() -> Array:
	var ids := host.bots.keys()
	ids.sort()
	ids.reverse()
	return ids


func _bots_with(role: int) -> Array:
	return _bots().filter(func(id): return host.actors[id].role == role)


## Moves an actor (bots and this device's player alike) to `at`, facing
## `face` if given, else facing the camera.
func _put(id: int, at: Vector3, face := Vector3.INF) -> void:
	var p := _spot_near(at, 0.0)
	var a: Dictionary = host.actors[id]
	a.pos = p
	a.state_t = host.time
	a.anim = Rules.Anim.IDLE
	var yaw := 0.0
	if face != Vector3.INF and Vector2(face.x - p.x, face.z - p.z).length() > 0.1:
		yaw = atan2(face.x - p.x, face.z - p.z)
	a.yaw = yaw
	if id == game.my_id:
		game.player.teleport(p)
		game.player._yaw = yaw
		game.player.avatar.rotation.y = yaw
		game.camera.snap_to(p)
	await get_tree().process_frame


## The nearest walkable point to `target`, `away` metres off towards the
## camera (or round the side if that's blocked).
func _spot_near(target: Vector3, away: float) -> Vector3:
	var v := game.village
	if away > 0.0:
		for deg in [0, 40, -40, 80, -80, 130, -130, 180]:
			var p := target + Vector3(0, 0, away).rotated(Vector3.UP, deg_to_rad(deg))
			if v.is_walkable(p):
				return Vector3(p.x, 0, p.z)
	return v._to_world(v._nearest_open(v._to_cell(target)))


func _nearest_lantern(pos: Vector3) -> int:
	var best := 0
	for i in host.lantern_pos.size():
		if host.lantern_pos[i].distance_to(pos) < host.lantern_pos[best].distance_to(pos):
			best = i
	return best


func _lanterns_off(center: Vector3, radius: float) -> void:
	for i in host.lantern_pos.size():
		if Vector2(host.lantern_pos[i].x - center.x, host.lantern_pos[i].z - center.z).length() <= radius:
			host.lit[i] = false
	host._send_lanterns()


func _banish(a: Dictionary) -> void:
	a.alive = false
	a.ghost = true
	a.banished = true


func _take_some(hollow: Dictionary, villagers: Array, n: int) -> void:
	for v in villagers.slice(0, n):
		host._take(hollow, v)


## Lets a meeting run for `seconds` of game time, twice as fast.
func _talk(seconds: float) -> void:
	Engine.time_scale = 2.0
	await _wait(seconds)
	Engine.time_scale = 1.0
	await _wait(0.2)


## Ends the vote with these counts ({target: votes}), filling in the
## remaining voters in order.
func _reveal(counts: Dictionary) -> void:
	var voters: Array = host._voters()
	var votes := {}
	var i := 0
	for target in counts:
		for n in counts[target]:
			while i < voters.size() and (voters[i] == target):
				i += 1
			if i >= voters.size():
				break
			votes[voters[i]] = target
			i += 1
	host.meeting.votes = votes
	host._reveal()
	await _wait(1.0)


## Ends the talk, if it's still going, and waits for the vote.
func _to_vote() -> void:
	if host.meeting.phase == Rules.MeetingPhase.DISCUSS:
		host.meeting.left = 0.0
	while host.phase == Rules.Phase.MEETING and host.meeting.phase == Rules.MeetingPhase.DISCUSS:
		await get_tree().process_frame
	await _wait(0.4)


func _end_meeting() -> void:
	host.meeting.left = 0.0
	while host.phase == Rules.Phase.MEETING:
		await get_tree().process_frame
	await _wait(0.5)


func _press_picker(label: String) -> void:
	for b in game.hud.meeting._picker_grid.get_children():
		if b is Button and b.text.to_lower() == label.to_lower():
			b.pressed.emit()
			return
	push_warning("No quick chat choice %s" % label)


func _overview() -> void:
	_overview_cam = Camera3D.new()
	game.add_child(_overview_cam)
	_overview_cam.fov = 45.0
	_overview_cam.far = 200.0
	_overview_cam.global_position = Vector3(0, 48, 35)
	_overview_cam.look_at(Vector3(0, 0, 2.5))
	_overview_cam.current = true
	game.hud.visible = false
	await _wait(0.5)


func _end_overview() -> void:
	_overview_cam.queue_free()
	game.camera.current = true
	game.hud.visible = true


# --- Menus ---------------------------------------------------------------------

func _title() -> Node:
	var t: Node = await _scene("res://game/ui/title.tscn")
	await _wait(1.0)
	return t


func _scene(path: String) -> Node:
	LGScenes.change_scene(path)
	return await _settled()


## The current scene once every queued scene change has finished.
func _settled() -> Node:
	await get_tree().process_frame
	while LGScenes.is_busy():
		await get_tree().process_frame
	return get_tree().current_scene


func _sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


func _use_pad(on: bool) -> void:
	LGInput.family = "xbox" if on else "keyboard"
	LGInput.device_changed.emit(LGInput.family)


# --- Saving --------------------------------------------------------------------

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(group: String, file: String, caption: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_root.path_join(group))
	img.save_jpg(_root.path_join(group).path_join(file + ".jpg"), 0.85)
	_shots.append([group, file, caption])
	print("Saved ", group, "/", file)


## A README.md beside the screenshots listing every one, group by group.
func _write_index() -> void:
	var lines := ["# Screenshots", "",
		"Every screen of Graveyard Hollow, made with:", "",
		"    xvfb-run -a -s \"-screen 0 1280x800x24\" godot --path . --resolution 1280x800 tools/screenshot.tscn -- --all=docs/screenshots", "",
		"The nights are staged by `tools/screenshot_gallery.gd`: it picks your role, places the bots and puts out lanterns where a shot needs the dark. Install `mesa-vulkan-drivers` first, so Godot renders with Vulkan as the game does rather than a paler OpenGL fallback.", ""]
	for g in GROUPS:
		var mine := _shots.filter(func(s): return s[0] == g[0])
		if mine.is_empty():
			continue
		lines.append("## %s" % g[1])
		lines.append("")
		for s in mine:
			lines.append("**%s**" % s[2])
			lines.append("")
			lines.append("![%s](%s/%s.jpg)" % [s[2], s[0], s[1]])
			lines.append("")
	var out := FileAccess.open(_root.path_join("README.md"), FileAccess.WRITE)
	if out:
		out.store_string("\n".join(lines))


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_saved_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
