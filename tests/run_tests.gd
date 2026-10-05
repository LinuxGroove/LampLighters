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
	await _test_bot_nights(games)
	print("\n%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", what)


func _test_join_codes() -> void:
	for case in [["192.168.1.23", 24680], ["10.0.0.5", 24680], ["172.16.4.200", 31000]]:
		var code := JoinCode.encode(case[0], case[1], 24680)
		var back := JoinCode.decode(JoinCode.pretty(code).to_lower(), 24680)
		check(back.get("ip") == case[0] and back.get("port") == case[1], "join code round trip %s" % [case])
	check(JoinCode.decode("not a code!", 24680).is_empty(), "bad join code is rejected")


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
		var steps := 0
		var limit := int((host.night_total + 600.0) * 30.0)
		while host.phase != Rules.Phase.ENDED and steps < limit:
			host._process(1.0 / 30.0)
			steps += 1
			if host.phase == Rules.Phase.MEETING and not was_meeting:
				meetings += 1
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
