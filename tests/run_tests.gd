extends Node
## Headless tests: run with
##   godot --headless --path . tests/run_tests.tscn
## Add `-- --games=N` to simulate more bot nights. Exits non-zero on failure.

var failures := 0
var checks := 0


func _ready() -> void:
	var games := 4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = arg.substr(8).to_int()
	LGTheme.apply(get_tree().root)
	LGInput.register_actions(GameConfig.ACTIONS)
	_test_join_codes()
	_test_roles()
	_test_chores()
	_test_quick_chat()
	await _test_scene_switcher()
	await _test_option_rows()
	await _test_tutorial_ui()
	await _test_title_menu()
	_test_leaderboard_panel()
	_test_name_maker()
	await _test_quick_match_bots()
	await _test_practice()
	await _test_bot_nights(games)
	print("\n%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", what)


## A burst of scene changes (a double press, or a return to the lobby right
## before a new match) must leave exactly one scene, the last one asked for.
func _test_scene_switcher() -> void:
	var tree := get_tree()
	await tree.process_frame
	var placeholder := Node.new()
	placeholder.name = "Placeholder"
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	var made := []
	for n in ["SceneA", "SceneB", "SceneC"]:
		var node := Node.new()
		node.name = n
		var packed := PackedScene.new()
		packed.pack(node)
		node.free()
		made.append(packed)
	LGScenes.change_scene(made[0])
	LGScenes.change_scene(made[1])
	LGScenes.change_scene(made[2])
	var waited := 0
	while (LGScenes.is_busy() or tree.current_scene == placeholder) and waited < 300:
		await tree.process_frame
		waited += 1
	await tree.process_frame
	var found := []
	for c in tree.root.get_children():
		if str(c.name).begins_with("Scene") or c.name == "Placeholder":
			found.append(str(c.name))
	check(found == ["SceneC"], "a burst of scene changes leaves only the last scene (got %s)" % [found])
	for c in tree.root.get_children():
		if str(c.name).begins_with("Scene"):
			c.free()
	tree.current_scene = self


## Option rows by controller: left and right move between panels until A is
## pressed on a row; then they change its value, and A again finishes.
func _test_option_rows() -> void:
	var tree := get_tree()
	Session.start_solo(5)
	var lobby: Node = (load("res://game/ui/lobby.tscn") as PackedScene).instantiate()
	tree.root.add_child(lobby)
	for i in 3:
		await tree.process_frame
	var row: LGCycler = lobby._cyclers["night_minutes"]
	var before: Variant = row.value()
	row.grab_focus()
	await tree.process_frame
	await _press("ui_left")
	var owner := get_viewport().gui_get_focus_owner()
	check(row.value() == before, "left on a row that isn't being edited keeps its value")
	check(owner != null and owner != row and owner.get_global_rect().position.x < row.get_global_rect().position.x,
		"left on a house rule moves focus to the left panel (focus on %s)" % [owner])
	row.grab_focus()
	await tree.process_frame
	await _press("ui_accept")
	check(row.editing, "A starts editing a row")
	await _press("ui_right")
	check(row.value() != before and get_viewport().gui_get_focus_owner() == row, "right while editing changes the value")
	await _press("ui_accept")
	check(not row.editing, "A again finishes editing")
	lobby.free()
	Session.leave()
	check(not LGScenes.is_busy(), "a freed lobby doesn't react when the session ends")


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _test_join_codes() -> void:
	for case in [["192.168.1.23", 24680], ["10.0.0.5", 24680], ["172.16.4.200", 31000]]:
		var code := JoinCode.encode(case[0], case[1], 24680)
		var back := JoinCode.decode(JoinCode.pretty(code).to_lower(), 24680)
		check(back.get("ip") == case[0] and back.get("port") == case[1], "join code round trip %s" % [case])
	check(JoinCode.decode("not a code!", 24680).is_empty(), "bad join code is rejected")
	for case in [["192.168.0.1", 24680], ["8.8.8.8", 40000], ["255.255.255.255", 65535]]:
		var code := JoinCode.encode(case[0], case[1], 24680)
		for pair in [["0", "O"], ["1", "I"], ["2", "Z"], ["5", "S"], ["8", "B"]]:
			code = code.replace(pair[0], pair[1])
		var back := JoinCode.decode(code, 24680)
		check(back.get("ip") == case[0] and back.get("port") == case[1], "a code typed with look-alike letters still works %s" % [case])
	var short := JoinCode.encode("192.168.1.23", 24680, 24680)
	check(JoinCode.decode(short.substr(0, short.length() - 1), 24680).is_empty(), "a code missing a character is rejected")


func _test_roles() -> void:
	var rng := RandomNumberGenerator.new()
	for n in range(GameConfig.MIN_PLAYERS, GameConfig.MAX_PLAYERS + 1):
		rng.seed = n
		var ids := []
		for i in n:
			ids.append(i + 1)
		var roles := Rules.deal_roles(ids, Rules.DEFAULT_SETTINGS, rng)
		var counts := {}
		for id in roles:
			counts[roles[id]] = int(counts.get(roles[id], 0)) + 1
		check(roles.size() == n, "%d players all get a role" % n)
		check(int(counts.get(Rules.Role.HOLLOW, 0)) == (1 if n <= 6 else 2), "%d players: Hollow count" % n)
		check(int(counts.get(Rules.Role.SEER, 0)) == (1 if n >= 5 else 0), "%d players: Seer count" % n)
		check(int(counts.get(Rules.Role.WATCHMAN, 0)) == (1 if n >= 7 else 0), "%d players: Watchman count" % n)


func _test_chores() -> void:
	var village: Village = (load("res://game/world/moonpatch_village.tscn") as PackedScene).instantiate()
	add_child(village)
	var stations := village.stations()
	for key in Rules.CHORES:
		for step in Rules.CHORES[key].steps:
			check(stations.has(step.station), "chore %s has station %s" % [key, step.station])
			if stations.has(step.station) and not step.get("dark", false):
				var sp: Vector3 = stations[step.station].global_position
				var lit_near := village.lanterns().any(func(l): return Vector2(l.global_position.x - sp.x, l.global_position.z - sp.z).length() <= Rules.WORK_LIGHT_RADIUS)
				check(lit_near, "a lantern lights the %s station" % step.station)
			if stations.has(step.station):
				var p: Vector3 = stations[step.station].global_position
				var path := village.find_path(village.bell_position() + Vector3(2, 0, 2), p)
				check(path.size() > 0 and path[path.size() - 1].distance_to(Vector3(p.x, 0, p.z)) < 1.5, "a path reaches %s" % step.station)
	for l in village.lanterns():
		var path := village.find_path(Vector3(0, 0, 3), l.global_position)
		check(path.size() > 0 and path[path.size() - 1].distance_to(l.global_position * Vector3(1, 0, 1)) < Rules.INTERACT_RANGE, "a path reaches lantern %d" % l.lantern_id)
	village.queue_free()


func _test_quick_chat() -> void:
	var game: Game = (load("res://game/game.gd") as GDScript).new()
	game.roster = {1: {"name": "Ada", "look": 0}}
	game.landmarks = ["the square", "the chapel"]
	check(game.quick_chat_text(3, 1, 1) == "I saw Ada near the chapel.", "quick chat fills in names and places")
	check(game.quick_chat_text(99, 1, 1) == "", "unknown quick chat is ignored")
	game.free()


## Plays whole nights with bots only, stepping the host by hand at 30 Hz.
func _test_bot_nights(games: int) -> void:
	await get_tree().process_frame
	var wins := {Rules.Team.VILLAGE: 0, Rules.Team.HOLLOW: 0}
	for g in games:
		Session.start_solo(0)
		var players := {}
		var n := 6 + (g % 5)
		for i in n:
			var id := 1 if i == 0 else -i
			players[id] = {"name": GameConfig.BOT_NAMES[i], "look": i, "bot": true}
		var settings := Rules.DEFAULT_SETTINGS.duplicate()
		settings.discussion_seconds = 20
		settings.vote_seconds = 15
		settings.ai_brains = false
		var config := {"seed": 1000 + g, "players": players, "settings": settings,
			"map": "res://game/world/moonpatch_village.tscn"}
		Session.in_match = true
		var game: Game = (load("res://game/game.tscn") as PackedScene).instantiate()
		game.config = config
		get_tree().root.add_child(game)
		await get_tree().process_frame
		var host := game.host
		host.set_process(false)
		var meetings := 0
		var was_meeting := false
		var checked_votes := false
		var steps := 0
		var limit := int((host.night_total + 600.0) * 30.0)
		while host.phase != Rules.Phase.ENDED and steps < limit:
			host._process(1.0 / 30.0)
			steps += 1
			if host.phase == Rules.Phase.MEETING and not was_meeting:
				meetings += 1
				checked_votes = false
			if host.phase == Rules.Phase.MEETING and host.meeting.phase == Rules.MeetingPhase.REVEAL and not checked_votes:
				checked_votes = true
				_check_votes_match_words(host, g)
			was_meeting = host.phase == Rules.Phase.MEETING
			if steps % 600 == 0:
				await get_tree().process_frame
		var res := host.result
		check(host.phase == Rules.Phase.ENDED, "game %d ends" % g)
		check(not res.is_empty() and res.has("winner"), "game %d has a winner" % g)
		check(host.chores_done > 0, "game %d: bots did chores" % g)
		if res.has("winner"):
			wins[res.winner] += 1
		print("game %d: %d players, %s won (%s) after %d s, chores %d/%d, lanterns %d/%d, %s" % [
			g, n, "village" if res.get("winner") == Rules.Team.VILLAGE else "Hollow", res.get("reason"),
			int(res.get("time", 0)), host.chores_done, host.chores_total, host.lit_count(), host.lit.size(), host.stats])
		check(meetings == host.stats.meetings, "game %d: meeting count matches" % g)
		game.queue_free()
		await get_tree().process_frame
		Session.leave()
	print("village %d, Hollow %d" % [wins[Rules.Team.VILLAGE], wins[Rules.Team.HOLLOW]])


## Every bot's vote must follow the last side it took out loud in the meeting
## (counting the player just banished, who is already out of the voters),
## and a bot that said nothing about anyone may only skip.
func _check_votes_match_words(host: MatchHost, g: int) -> void:
	var among := host._voters()
	var out: int = host.meeting.get("result", {}).get("banished", Rules.SKIP_VOTE)
	if out != Rules.SKIP_VOTE:
		among.append(out)
	for voter in host.meeting.votes:
		if not host.bots.has(voter):
			continue
		var bot: BotBrain = host.bots[voter]
		var side := BotBrain.NO_STANCE
		var lines := []
		for line in host.meeting.log:
			if line.id == voter:
				lines.append(line.text)
				var s := bot.stance_of(line.text, among)
				if s != BotBrain.NO_STANCE:
					side = s
		var vote: int = host.meeting.votes[voter]
		var ok := vote == side or (side == BotBrain.NO_STANCE and vote == Rules.SKIP_VOTE)
		check(ok, "game %d: %s voted %s after saying %s" % [g, host.actors[voter].name,
			"skip" if vote == Rules.SKIP_VOTE else host.actors[vote].name, lines])


## The practice round: everyone is a Lamplighter, one lantern starts dark, the
## night never ends, and a bell meeting runs its course and hands back the night.
func _test_practice() -> void:
	await get_tree().process_frame
	Session.start_solo(0)
	var players := {}
	for i in 4:
		players[1 if i == 0 else -i] = {"name": GameConfig.BOT_NAMES[i], "look": i, "bot": i > 0}
	var config := {"seed": 7, "players": players, "settings": Rules.DEFAULT_SETTINGS.duplicate(),
		"map": "res://game/world/moonpatch_village.tscn", "practice": true}
	Session.in_match = true
	var game: Game = (load("res://game/game.tscn") as PackedScene).instantiate()
	game.config = config
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var host := game.host
	host.set_process(false)
	for i in 5:
		host._process(1.0 / 30.0)
		await get_tree().process_frame
	check(host.practice, "practice flag reaches the host")
	check(host.actors.values().all(func(a): return a.role == Rules.Role.LAMPLIGHTER), "practice: everyone is a Lamplighter")
	check(host.lit.size() - host.lit_count() == 1, "practice: exactly one lantern starts dark")
	check(game.player != null and game.hud.guide != null, "practice: the guide is running")
	check(game.hud.hints == null, "practice: no one-time tips")
	await _drive_guide(game, host)
	var start_bots: Array = host.bots.keys().map(func(id): return host.actors[id].pos)
	for i in 30 * 600:
		host._process(1.0 / 30.0)
		if i % 900 == 0:
			await get_tree().process_frame
	check(host.phase == Rules.Phase.NIGHT, "practice: ten quiet minutes don't end the round")
	check(host.bots.keys().map(func(id): return host.actors[id].pos) == start_bots, "practice: bots stand still")
	check(host.phase == Rules.Phase.NIGHT, "practice: the night resumes after the meeting")
	game.queue_free()
	await get_tree().process_frame
	Session.leave()


func _button_texts(title: Node) -> Array:
	return title._col.get_children().filter(func(c): return c is Button).map(func(b): return b.text)


## The title menu keeps local play and the tutorial on their own screens.
func _test_title_menu() -> void:
	LGSettings.set_value("player", "name", "Tester", false)
	LGSettings.set_value("tutorial", "welcomed", true, false)
	var title: Node = load("res://game/ui/title.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	var main := _button_texts(title)
	for t in ["How to play", "Play with bots", "Local network play", "Play online"]:
		check(t in main, "title menu has %s" % t)
	for t in ["Practice round", "Host on this network", "Join on this network"]:
		check(not t in main, "%s moved off the title menu" % t)
	title._show_howto_menu()
	check(_button_texts(title) == ["Tutorial", "Practice round", "Back"], "how to play holds the tutorial and practice")
	await get_tree().process_frame
	title._show_local()
	check(_button_texts(title) == ["Host on this network", "Join on this network", "Back"], "local network play holds host and join")
	await get_tree().process_frame
	var online_was: bool = LGSettings.get_value("online", "enabled")
	LGSettings.set_value("online", "enabled", true, false)
	title._show_online()
	check("Leaderboards" in _button_texts(title), "play online offers leaderboards")
	LGSettings.set_value("online", "enabled", online_was, false)
	# Let the menu's deferred focus land before freeing it.
	await get_tree().process_frame
	title.queue_free()
	await get_tree().process_frame


## Bot names: player-like, unique, short enough for a name tag.
func _test_name_maker() -> void:
	var used := ["MossyOtter"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 200:
		var n := LGNameMaker.make(used, rng)
		check(n.length() <= 16, "name %s fits in 16 letters" % n)
		check(not n.to_lower() in used.map(func(u): return u.to_lower()), "name %s is unique" % n)
		used.append(n)
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	check(LGNameMaker.make([], a) == LGNameMaker.make([], b), "the same seed makes the same name")
	check(LGNameMaker.make(["Ab"], null, 16, ["A"], ["b"]).begins_with("Ab"), "taken names get a number")


## Quick match with nobody else around: you and a random number of named bots,
## and a countdown that only the host acts on.
func _test_quick_match_bots() -> void:
	Session.start_quick_solo()
	var size := Session.players.size()
	check(Session.quick and Session.mode == Session.Mode.SOLO, "quick match falls back to a solo game")
	check(size >= GameConfig.QUICK_MATCH_SIZE.x and size <= GameConfig.QUICK_MATCH_SIZE.y, "quick match has %d villagers" % size)
	var names: Array = Session.players.values().map(func(p): return p.name)
	var bots: Array = Session.players.values().filter(func(p): return p.bot)
	check(bots.size() == size - 1, "everyone else is a bot")
	check(bots.all(func(p): return not p.name in GameConfig.BOT_NAMES), "quick-match bots get made-up names")
	check(names.size() == size and names.all(func(n): return names.count(n) == 1), "bot names are unique")
	check(Session.can_start(), "a quick-match village can start")
	var left := Session.quick_seconds_left()
	check(left > Session.QUICK_COUNTDOWN - 1.0 and left <= Session.QUICK_COUNTDOWN, "the countdown is running (%.1f s)" % left)
	Session.leave()
	check(not Session.quick and Session.quick_seconds_left() == 0.0, "leaving ends quick match")
	# A guest learns the countdown from the host, but never acts on it.
	Session._h_countdown(5.0)
	check(Session.quick and Session.quick_seconds_left() > 4.0, "the host's countdown reaches a guest")
	Session._quick_start_msec = 1
	Session._process(0.0)
	check(not Session.in_match, "only the host starts the night")
	Session.leave()
	# Ordinary bots keep the game's own names.
	Session.start_solo(1)
	check(Session.players.values().filter(func(p): return p.bot)[0].name in GameConfig.BOT_NAMES, "bots outside quick match keep their usual names")
	Session.leave()
	await get_tree().process_frame


## Leaderboard rows: the top list, you highlighted, and your rank below it.
func _test_leaderboard_panel() -> void:
	var panel := LGLeaderboardPanel.new()
	panel.setup("graveyard-hollow", "Tester", [["wins_weekly", "This week"], ["wins", "All time"]])
	panel.build()
	panel.show_board({"top": [], "mine": null})
	check(panel._list.get_child_count() == 1 and panel._mine.text != "", "an empty board says so")
	var top := []
	for i in 10:
		top.append({"rank": i + 1, "name": "P%d" % i, "score": 20 - i, "me": false})
	panel.show_board({"top": top, "mine": {"rank": 14, "name": "Tester", "score": 3, "me": true}})
	check(panel._list.get_child_count() == 10, "ten rows on a full board")
	check(panel._mine.text.contains("#14"), "your rank shows when you're below the top ten")
	top[2].me = true
	panel.show_board({"top": top, "mine": top[2]})
	check(panel._mine.text == "", "no separate line when you're in the top ten")
	panel.free()
	# Your own record, above the boards.
	var title_script: Script = load("res://game/ui/title.gd")
	var rec := LGLeaderboardPanel.new()
	rec.setup("graveyard-hollow", "Tester", [["wins", "All time"]], title_script.record_text)
	rec.build()
	check(rec._record.visible, "the record line shows when the game gives one")
	rec.show_record({})
	check(rec._record.text.begins_with("No online rounds yet"), "a player with no online games is told how to start a record")
	rec.show_record({"rounds": 12, "wins": 5, "village_rounds": 8, "village_wins": 3, "hollow_rounds": 4, "hollow_wins": 2, "survived": 7})
	check(rec._record.text == "Your online record: 12 rounds, 5 wins (3 as a Lamplighter, 2 as the Hollow), survived 7.", "the record reads: %s" % rec._record.text)
	rec.free()
	var plain := LGLeaderboardPanel.new()
	plain.setup("graveyard-hollow", "Tester", [["wins", "All time"]])
	plain.build()
	check(not plain._record.visible, "no record line without a record function")
	plain.free()


## The how-to pages and role cards build and page through without errors.
func _test_tutorial_ui() -> void:
	var howto := HowToPanel.new()
	add_child(howto)
	var closed := [false]
	howto.closed.connect(func(): closed[0] = true)
	howto.open()
	await get_tree().process_frame
	var pages := HowToPanel.pages().size()
	for i in pages:
		howto._go(1)
	check(closed[0] and not howto.visible, "how to play closes after the last page (%d pages)" % pages)
	howto.queue_free()
	var card := RoleCard.new()
	add_child(card)
	for role in Rules.ROLE_NAMES:
		check(Rules.ROLE_CARDS.has(role), "role %d has a card" % role)
		card.show_role(role, ["Ada"])
		check(card.visible, "role card opens for role %d" % role)
		card.close()
	card.queue_free()
	await get_tree().process_frame


## Plays the practice round the way a player would and checks the guide advances.
func _drive_guide(game: Game, host: MatchHost) -> void:
	var guide: PracticeGuide = game.hud.guide
	check(guide._step == 0, "guide starts on the walking step")
	for i in 12:
		game.player.global_position += Vector3(1, 0, 0)
		await get_tree().process_frame
	check(guide._step == 1, "walking moves the guide to the lantern step")
	var dark := host.lit.find(false)
	check(dark >= 0, "a dark lantern waits to be relit")
	host.actors[1].pos = host.lantern_pos[dark] + Vector3(1, 0, 0)
	check(host.act(1, Rules.Act.RELIGHT_START, dark), "relight starts")
	for i in 70:
		host._process(1.0 / 30.0)
	check(host.act(1, Rules.Act.RELIGHT_DONE, dark), "relight finishes")
	await get_tree().process_frame
	await get_tree().process_frame
	check(guide._step == 2, "relighting moves the guide to the chores")
	for n in PracticeGuide.CHORES_NEEDED:
		var chore := game.current_chore()
		check(not chore.is_empty(), "chore %d is waiting" % n)
		var index: int = chore.index
		host.actors[1].pos = host.station_position(chore.data.station)
		check(host.act(1, Rules.Act.CHORE_START, index), "chore %d starts (%s)" % [n, chore.key])
		for i in 90:
			host._process(1.0 / 30.0)
		check(host.act(1, Rules.Act.CHORE_DONE, index), "chore %d finishes" % n)
		await get_tree().process_frame
	await get_tree().process_frame
	check(guide._step == 3, "three chores move the guide to the map")
	game.hud.map.open()
	await get_tree().process_frame
	game.hud.map.close()
	check(guide._step == 4, "opening the map moves the guide to the bell")
	host.actors[1].pos = host.village.bell_position()
	check(host.act(1, Rules.Act.BELL, 0), "the bell rings")
	await get_tree().process_frame
	check(guide._step == 5, "the meeting moves the guide on")
	var steps := 0
	while host.phase == Rules.Phase.MEETING and steps < 30 * 120:
		host._process(1.0 / 30.0)
		if host.meeting.get("phase") == Rules.MeetingPhase.VOTE and not host.meeting.votes.has(1):
			host.vote(1, Rules.SKIP_VOTE)
		steps += 1
	await get_tree().process_frame
	await get_tree().process_frame
	check(guide.blocking(), "the guide ends with the completion panel")
