class_name MatchHost
extends Node
## The authoritative match, run only on the host.
##
## Holds every secret (roles, who took whom, every position) and sends each
## player only what their own character can see. Clients ask to do things
## and the host checks distance, timing, cooldowns and light before agreeing.
## Bots are driven from here and use the same checks as people.

signal ended(result: Dictionary)

const SNAPSHOT_RATE := 20.0
const STATUS_RATE := 1.0
const LOAD_TIMEOUT := 20.0
const PRINT_STEP := 0.9
const SPEED_SLACK := 1.6
const RANGE_SLACK := 0.6

var net: Node  # the Game node: send(), broadcast(), village
var village: Village
var settings := {}
var rng := RandomNumberGenerator.new()
## id -> actor state Dictionary (see _new_actor)
var actors := {}
var lit: Array[bool] = []
var lantern_pos: Array[Vector3] = []
var remains: Array = []  # {id, victim, pos, t}
var prints: Array = []  # {x, z, t, id}
var phase := Rules.Phase.LOADING
var time := 0.0
var night_total := 0.0
var night_left := 0.0
var meeting := {}
var chores_total := 0
var chores_done := 0
var result := {}
## Counts for the end screen and for balancing.
var stats := {"takes": 0, "snuffs": 0, "relights": 0, "meetings": 0, "banished_hollow": 0, "banished_village": 0}
var bots := {}  # id -> BotBrain
var talk: BotTalk

var _snap_t := 0.0
var _status_t := 0.0
var _load_t := 0.0
var _next_remains := 1
var _humans: Array[int] = []


func setup(config: Dictionary, p_net: Node, p_village: Village) -> void:
	net = p_net
	village = p_village
	rng.seed = int(config.get("seed", 1))
	settings = Rules.DEFAULT_SETTINGS.duplicate()
	settings.merge(config.get("settings", {}), true)
	var players: Dictionary = config.players
	var ids := players.keys()
	ids.sort()
	var roles := Rules.deal_roles(ids, settings, rng)
	var spawns := village.spawn_points()
	for i in ids.size():
		var id: int = ids[i]
		var a := _new_actor(id, players[id], roles[id], spawns[i % spawns.size()])
		actors[id] = a
		if Rules.team_of(a.role) == Rules.Team.VILLAGE:
			chores_total += a.chores.size()
		if a.bot:
			bots[id] = BotBrain.new(self, id)
		else:
			_humans.append(id)
	for lantern in village.lanterns():
		lit.append(true)
		lantern_pos.append((lantern as Node3D).global_position)
	night_total = float(settings.night_minutes) * 60.0
	night_left = night_total
	talk = BotTalk.new(self)


func _new_actor(id: int, p: Dictionary, role: int, spawn: Vector3) -> Dictionary:
	var chores := []
	for key in Rules.deal_chores(int(settings.chores_each), rng):
		chores.append({"key": key, "step": 0, "done": false})
	return {
		"id": id, "name": str(p.get("name", "?")), "look": int(p.get("look", 0)),
		"bot": bool(p.get("bot", false)), "role": role,
		"alive": true, "ghost": false, "out": false, "banished": false,
		"pos": spawn, "yaw": 0.0, "anim": Rules.Anim.IDLE, "carry": "",
		"chores": chores, "action": {},
		"snuff_ready": Rules.FIRST_COOLDOWN, "take_ready": Rules.FIRST_COOLDOWN,
		"bell_left": int(settings.bell_uses), "bell_ready": Rules.BELL_COOLDOWN,
		"seer_used": false, "flicker_used": false,
		"state_t": 0.0, "print_pos": spawn, "taken_by": 0,
	}


# --- Main loop ----------------------------------------------------------

func _process(delta: float) -> void:
	match phase:
		Rules.Phase.LOADING:
			_load_t += delta
			var waiting := _humans.filter(func(id): return not Session.loaded_peers.has(id) and id != net.my_id)
			if waiting.is_empty() or _load_t > LOAD_TIMEOUT:
				_begin(waiting)
			return
		Rules.Phase.NIGHT:
			time += delta
			night_left -= delta
			for bot in bots.values():
				bot.tick(delta)
			_update_prints()
			_check_win()
		Rules.Phase.MEETING:
			time += delta
			_meeting_tick(delta)
		Rules.Phase.ENDED:
			return
	_snap_t += delta
	if _snap_t >= 1.0 / SNAPSHOT_RATE:
		_snap_t = 0.0
		_send_snapshots()
	_status_t += delta
	if _status_t >= 1.0 / STATUS_RATE:
		_status_t = 0.0
		_send_status()


func _begin(missing: Array) -> void:
	for id in missing:
		on_player_left(id)
	phase = Rules.Phase.NIGHT
	for id in _humans:
		if not actors[id].out:
			net.send(id, "_h_intro", [_intro_for(id)])
	_send_lanterns()
	_send_status()


func _intro_for(id: int) -> Dictionary:
	var a: Dictionary = actors[id]
	var roster := {}
	for other in actors.values():
		roster[other.id] = {"name": other.name, "look": other.look}
	var allies := []
	if a.role == Rules.Role.HOLLOW:
		for other in actors.values():
			if other.role == Rules.Role.HOLLOW and other.id != id:
				allies.append(other.id)
	return {
		"id": id, "role": a.role, "allies": allies, "roster": roster,
		"pos": a.pos, "night": night_left, "settings": settings,
		"you": _private_state(id),
	}


# --- Requests from players (people through RPC, bots directly) -----------

## Client position report. Movement is client-side for responsiveness; the
## host clamps speed and keeps people inside the map.
func on_state(id: int, pos: Vector3, yaw: float, anim: int) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.out or phase != Rules.Phase.NIGHT:
		return
	var dt := maxf(time - float(a.state_t), 0.05)
	a.state_t = time
	pos.y = 0.0
	pos = village.clamp_to_bounds(pos)
	var speed := Rules.GHOST_SPEED if a.ghost else Rules.WALK_SPEED
	var max_step := speed * dt * SPEED_SLACK + 0.3
	var step := pos - (a.pos as Vector3)
	if step.length() > max_step:
		pos = a.pos + step.normalized() * max_step
		if step.length() - max_step > 1.5:
			net.send(id, "_h_teleport", [pos])
	a.pos = pos
	a.yaw = yaw
	a.anim = clampi(anim, 0, Rules.Anim.SIT)
	if a.action and a.action.kind == Rules.Act.CHORE_START and _station_distance(a) > Rules.INTERACT_RANGE + RANGE_SLACK * 2.0:
		a.action = {}


## Returns true when the host accepted the request.
func act(id: int, kind: int, target: int) -> bool:
	if phase != Rules.Phase.NIGHT:
		return false
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.out:
		return false
	match kind:
		Rules.Act.RELIGHT_START:
			if a.ghost or not _valid_lantern(target) or lit[target] \
					or _near(a, lantern_pos[target], Rules.INTERACT_RANGE) == false:
				return _fail(id, "")
			a.action = {"kind": kind, "target": target, "start": time}
			a.anim = Rules.Anim.INTERACT
			return true
		Rules.Act.RELIGHT_DONE:
			if not _action_is(a, Rules.Act.RELIGHT_START, target, Rules.RELIGHT_TIME - 0.3) \
					or not _near(a, lantern_pos[target], Rules.INTERACT_RANGE):
				return _fail(id, "")
			a.action = {}
			if not lit[target]:
				_set_lit(target, true)
				stats.relights += 1
				_notice(a, "relit", {"lantern": target})
			return true
		Rules.Act.CHORE_START:
			if target < 0 or target >= a.chores.size() or a.chores[target].done:
				return _fail(id, "")
			if not _near(a, _station_pos(a, target), Rules.INTERACT_RANGE + 0.4):
				return _fail(id, "Get closer.")
			if not _chore_step(a, target).get("dark", false) and not work_lit(_station_pos(a, target)):
				return _fail(id, "Too dark to work here. Relight a lantern nearby.")
			a.action = {"kind": kind, "target": target, "start": time}
			a.anim = Rules.Anim.INTERACT
			return true
		Rules.Act.CHORE_DONE:
			if target < 0 or target >= a.chores.size():
				return _fail(id, "")
			var step := _chore_step(a, target)
			if step.is_empty() or not _action_is(a, Rules.Act.CHORE_START, target, float(step.get("min", 1.0)) - 0.25):
				return _fail(id, "")
			a.action = {}
			_advance_chore(a, target)
			return true
		Rules.Act.SNUFF:
			if a.role != Rules.Role.HOLLOW or not a.alive or not _valid_lantern(target) or not lit[target]:
				return _fail(id, "")
			if not _near(a, lantern_pos[target], Rules.INTERACT_RANGE):
				return _fail(id, "Get closer.")
			if time < a.snuff_ready:
				return _fail(id, "Not yet.")
			_set_lit(target, false)
			stats.snuffs += 1
			a.snuff_ready = time + Rules.SNUFF_COOLDOWN
			_witness(a, "snuff", {"lantern": target})
			_send_private(id)
			return true
		Rules.Act.TAKE:
			var v: Dictionary = actors.get(target, {})
			if a.role != Rules.Role.HOLLOW or not a.alive or v.is_empty() or not v.alive or v.out \
					or v.role == Rules.Role.HOLLOW:
				return _fail(id, "")
			if not _near(a, v.pos, Rules.TAKE_RANGE):
				return _fail(id, "Get closer.")
			if lit_at(a.pos) or lit_at(v.pos):
				return _fail(id, "Too much light here.")
			if time < a.take_ready:
				return _fail(id, "Not yet.")
			_take(a, v)
			return true
		Rules.Act.REPORT:
			if not a.alive:
				return false
			for r in remains:
				if r.id == target and _near(a, r.pos, Rules.INTERACT_RANGE + 0.4):
					_start_meeting(id, "report", r)
					return true
			return _fail(id, "")
		Rules.Act.BELL:
			if not a.alive or not _near(a, village.bell_position(), Rules.BELL_RANGE):
				return _fail(id, "")
			if a.bell_left <= 0:
				return _fail(id, "You've rung the bell already tonight.")
			if time < a.bell_ready:
				return _fail(id, "The bell is still ringing out.")
			a.bell_left -= 1
			_start_meeting(id, "bell", {})
			return true
		Rules.Act.SEER:
			var t: Dictionary = actors.get(target, {})
			if a.role != Rules.Role.SEER or not a.alive or a.seer_used or t.is_empty() or not t.alive or t.out:
				return _fail(id, "")
			if not _near(a, t.pos, Rules.SEER_RANGE):
				return _fail(id, "Get closer.")
			a.seer_used = true
			var hollow: bool = t.role == Rules.Role.HOLLOW
			net.send(id, "_h_seer", [target, hollow])
			_send_private(id)
			if a.bot:
				bots[id].learn_seer(target, hollow)
			return true
		Rules.Act.FLICKER:
			if not a.ghost or a.role == Rules.Role.HOLLOW or a.flicker_used or not _valid_lantern(target) or not lit[target]:
				return _fail(id, "")
			if not _near(a, lantern_pos[target], Rules.INTERACT_RANGE + 1.5):
				return _fail(id, "Get closer.")
			a.flicker_used = true
			net.broadcast("_h_flicker", [target])
			for bot in bots.values():
				bot.notice_flicker(target)
			_send_private(id)
			return true
		Rules.Act.CANCEL:
			a.action = {}
			return true
	return false


func vote(id: int, target: int) -> void:
	if phase != Rules.Phase.MEETING or meeting.phase != Rules.MeetingPhase.VOTE:
		return
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or not a.alive or a.out or meeting.votes.has(id):
		return
	if target != Rules.SKIP_VOTE:
		var t: Dictionary = actors.get(target, {})
		if t.is_empty() or not t.alive or t.out:
			return
	meeting.votes[id] = target
	net.broadcast("_h_voted", [id])
	if meeting.votes.size() >= _voters().size():
		_reveal()


## A meeting statement, from quick-chat or a bot. `text` is already final.
func say(id: int, text: String) -> void:
	if phase != Rules.Phase.MEETING or meeting.phase == Rules.MeetingPhase.REVEAL:
		return
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or not a.alive or a.out:
		return
	var said: Dictionary = meeting.said
	said[id] = int(said.get(id, 0)) + 1
	if said[id] > 6:
		return
	text = text.strip_edges().left(160)
	meeting.log.append({"id": id, "text": text})
	net.broadcast("_h_said", [id, text])
	for bot in bots.values():
		bot.hear(id, text)


func emote(id: int, n: int) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.out:
		return
	for viewer in _humans:
		var v: Dictionary = actors[viewer]
		if viewer == id or (not v.out and can_see(v, a)):
			net.send(viewer, "_h_emote", [id, clampi(n, 1, 4)])


func on_player_left(id: int) -> void:
	var a: Dictionary = actors.get(id, {})
	if a.is_empty() or a.out:
		return
	a.out = true
	a.alive = false
	a.action = {}
	if Rules.team_of(a.role) == Rules.Team.VILLAGE:
		for c in a.chores:
			if not c.done:
				chores_total -= 1
	if phase == Rules.Phase.MEETING and meeting.phase == Rules.MeetingPhase.VOTE \
			and meeting.votes.size() >= _voters().size():
		_reveal()
	if phase != Rules.Phase.LOADING:
		_check_win()


# --- Rules helpers --------------------------------------------------------

func lit_at(pos: Vector3) -> bool:
	for i in lit.size():
		if lit[i] and _flat_dist(lantern_pos[i], pos) <= Rules.LANTERN_RADIUS:
			return true
	return false


## Whether a lit lantern is close enough to work by.
func work_lit(pos: Vector3) -> bool:
	for i in lit.size():
		if lit[i] and _flat_dist(lantern_pos[i], pos) <= Rules.WORK_LIGHT_RADIUS:
			return true
	return false


func lit_count() -> int:
	return lit.count(true)


## Whether viewer `v` can see actor `a` right now.
func can_see(v: Dictionary, a: Dictionary) -> bool:
	if a.out:
		return false
	if v.ghost:
		return true
	if a.ghost:
		return false
	if phase == Rules.Phase.MEETING:
		return true
	return can_see_pos(v, a.pos)


func can_see_pos(v: Dictionary, pos: Vector3) -> bool:
	if v.ghost or phase == Rules.Phase.MEETING:
		return true
	var d := _flat_dist(v.pos, pos)
	if d <= Rules.PERSONAL_LIGHT:
		return true
	return d <= Rules.VIEW_RADIUS and lit_at(pos)


func station_position(station_id: String) -> Vector3:
	var s: Dictionary = village.stations()
	return (s[station_id] as Node3D).global_position if s.has(station_id) else Vector3.ZERO


func chore_fraction() -> float:
	return 1.0 if chores_total <= 0 else float(chores_done) / float(chores_total)


func _chore_step(a: Dictionary, index: int) -> Dictionary:
	var c: Dictionary = a.chores[index]
	var steps: Array = Rules.CHORES[c.key].steps
	return steps[c.step] if c.step < steps.size() else {}


func _station_pos(a: Dictionary, index: int) -> Vector3:
	var step := _chore_step(a, index)
	return station_position(step.station) if not step.is_empty() else Vector3.INF


func _station_distance(a: Dictionary) -> float:
	var p := _station_pos(a, a.action.target)
	return INF if p == Vector3.INF else _flat_dist(a.pos, p)


func _advance_chore(a: Dictionary, index: int) -> void:
	var c: Dictionary = a.chores[index]
	var step := _chore_step(a, index)
	c.step += 1
	a.carry = str(step.get("carry", ""))
	if c.step >= Rules.CHORES[c.key].steps.size():
		c.done = true
		a.carry = ""
		if Rules.team_of(a.role) == Rules.Team.VILLAGE and not a.out:
			chores_done += 1
	_send_private(a.id)


func _action_is(a: Dictionary, kind: int, target: int, min_time: float) -> bool:
	var act: Dictionary = a.action
	return not act.is_empty() and act.kind == kind and act.target == target and time - float(act.start) >= min_time


func _valid_lantern(i: int) -> bool:
	return i >= 0 and i < lit.size()


func _near(a: Dictionary, pos: Vector3, reach: float) -> bool:
	return _flat_dist(a.pos, pos) <= reach + RANGE_SLACK


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _fail(id: int, reason: String) -> bool:
	if not actors[id].bot:
		net.send(id, "_h_denied", [reason])
		_send_private(id)
	return false


func _set_lit(i: int, on: bool) -> void:
	lit[i] = on
	_send_lanterns()


func _take(h: Dictionary, v: Dictionary) -> void:
	v.alive = false
	v.ghost = true
	v.action = {}
	v.carry = ""
	v.taken_by = h.id
	h.take_ready = time + Rules.TAKE_COOLDOWN
	stats.takes += 1
	h.snuff_ready = maxf(h.snuff_ready, time + 4.0)
	remains.append({"id": _next_remains, "victim": v.id, "pos": v.pos, "t": time})
	_next_remains += 1
	_witness(h, "take", {"victim": v.id})
	_send_private(h.id)
	if v.bot:
		bots[v.id].learn_taken(h.id)
	else:
		net.send(v.id, "_h_taken", [h.id])
		_send_private(v.id)
	_check_win()


## Lets bots that can see `who` remember what they just did.
func _witness(who: Dictionary, what: String, data: Dictionary) -> void:
	for bot in bots.values():
		var b: Dictionary = actors[bot.id]
		if b.id != who.id and b.alive and can_see(b, who):
			bot.witness(who.id, what, data)


func _notice(who: Dictionary, what: String, data: Dictionary) -> void:
	for bot in bots.values():
		if bot.id != who.id and can_see(actors[bot.id], who):
			bot.witness(who.id, what, data)


func _update_prints() -> void:
	for a in actors.values():
		if a.alive and not a.out and _flat_dist(a.pos, a.print_pos) >= PRINT_STEP:
			a.print_pos = a.pos
			prints.append({"x": a.pos.x, "z": a.pos.z, "t": time, "id": a.id})
	while not prints.is_empty() and time - float(prints[0].t) > Rules.FOOTPRINT_LIFE:
		prints.pop_front()


# --- Meetings -------------------------------------------------------------

func _start_meeting(caller: int, reason: String, body: Dictionary) -> void:
	phase = Rules.Phase.MEETING
	stats.meetings += 1
	var place := ""
	var victim := 0
	if not body.is_empty():
		victim = body.victim
		place = village.landmark_name(body.pos)
	var bodies := []
	for r in remains:
		bodies.append(r.victim)
	remains.clear()
	var present: Array = actors.values().filter(func(a): return not a.out)
	present.sort_custom(func(x, y): return x.id < y.id)
	var spots := village.gather_points(present.size())
	var center := Vector3.ZERO
	for p in spots:
		center += p
	center /= maxf(spots.size(), 1)
	for i in present.size():
		var a: Dictionary = present[i]
		a.action = {}
		a.carry = ""
		a.pos = spots[i]
		var to_center: Vector3 = center - spots[i]
		a.yaw = atan2(to_center.x, to_center.z)
		a.anim = Rules.Anim.IDLE
		if not a.bot:
			net.send(a.id, "_h_teleport", [a.pos])
	meeting = {
		"caller": caller, "reason": reason, "victim": victim, "place": place,
		"phase": Rules.MeetingPhase.DISCUSS, "left": float(settings.discussion_seconds),
		"votes": {}, "said": {}, "log": [], "taken": bodies,
	}
	var info := {
		"caller": caller, "reason": reason, "victim": victim, "place": place,
		"discuss": float(settings.discussion_seconds), "vote": float(settings.vote_seconds),
		"alive": _voters(), "taken": bodies,
	}
	net.broadcast("_h_meeting", [info])
	for id in _humans:
		_send_private(id)
	talk.begin_meeting(meeting)


func _meeting_tick(delta: float) -> void:
	meeting.left -= delta
	match meeting.phase:
		Rules.MeetingPhase.DISCUSS:
			talk.tick_discussion(delta)
			if meeting.left <= 0.0:
				meeting.phase = Rules.MeetingPhase.VOTE
				meeting.left = float(settings.vote_seconds)
				net.broadcast("_h_meeting_phase", [Rules.MeetingPhase.VOTE, meeting.left])
				talk.begin_vote()
		Rules.MeetingPhase.VOTE:
			talk.tick_vote(delta)
			if meeting.left <= 0.0:
				_reveal()
		Rules.MeetingPhase.REVEAL:
			if meeting.left <= 0.0:
				_end_meeting()


func _voters() -> Array:
	var out := []
	for a in actors.values():
		if a.alive and not a.out:
			out.append(a.id)
	out.sort()
	return out


func _reveal() -> void:
	if meeting.phase == Rules.MeetingPhase.REVEAL:
		return
	meeting.phase = Rules.MeetingPhase.REVEAL
	meeting.left = Rules.REVEAL_TIME
	var tally := {}
	for voter in meeting.votes:
		var t: int = meeting.votes[voter]
		tally[t] = int(tally.get(t, 0)) + 1
	var best := Rules.SKIP_VOTE
	var best_n := int(tally.get(Rules.SKIP_VOTE, 0))
	var tie := false
	for t in tally:
		if t == Rules.SKIP_VOTE:
			continue
		if tally[t] > best_n:
			best = t
			best_n = tally[t]
			tie = false
		elif tally[t] == best_n:
			tie = true
	if tie:
		best = Rules.SKIP_VOTE
	var res := {"tally": tally, "banished": best, "tie": tie}
	if not settings.anonymous_votes:
		res["votes"] = meeting.votes.duplicate()
	if best != Rules.SKIP_VOTE:
		var b: Dictionary = actors[best]
		b.alive = false
		b.ghost = true
		b.banished = true
		if b.role == Rules.Role.HOLLOW:
			stats.banished_hollow += 1
		else:
			stats.banished_village += 1
		if settings.reveal_on_banish:
			res["role"] = b.role
		if not b.bot:
			_send_private(best)
	meeting["result"] = res
	net.broadcast("_h_meeting_result", [res])
	for bot in bots.values():
		bot.learn_result(res)


func _end_meeting() -> void:
	var finished := _check_win()
	if finished:
		return
	phase = Rules.Phase.NIGHT
	for a in actors.values():
		a.flicker_used = false
		a.snuff_ready = maxf(a.snuff_ready, time + Rules.FIRST_COOLDOWN)
		a.take_ready = maxf(a.take_ready, time + Rules.FIRST_COOLDOWN * 1.5)
		a.bell_ready = time + Rules.BELL_COOLDOWN
		a.state_t = time
	meeting = {}
	net.broadcast("_h_meeting_end", [])
	for id in _humans:
		_send_private(id)
	for bot in bots.values():
		bot.after_meeting()


# --- Winning --------------------------------------------------------------

func _check_win() -> bool:
	if phase == Rules.Phase.ENDED:
		return true
	var hollow := 0
	var village_alive := 0
	for a in actors.values():
		if a.alive and not a.out:
			if a.role == Rules.Role.HOLLOW:
				hollow += 1
			else:
				village_alive += 1
	var needed := int(ceil(lit.size() * float(settings.dark_fraction)))
	if hollow == 0:
		return _end(Rules.Team.VILLAGE, "Every Hollow was found.")
	if hollow >= village_alive:
		return _end(Rules.Team.HOLLOW, "The Hollow outnumber the village.")
	if lit_count() < needed:
		return _end(Rules.Team.HOLLOW, "The village fell dark.")
	if night_left <= 0.0 and phase == Rules.Phase.NIGHT:
		if chore_fraction() >= float(settings.dawn_chore_goal):
			return _end(Rules.Team.VILLAGE, "Dawn broke over a busy village.")
		return _end(Rules.Team.HOLLOW, "Dawn came with too many chores undone.")
	return false


func _end(winner: int, reason: String) -> bool:
	phase = Rules.Phase.ENDED
	var roles := {}
	var players := {}
	for a in actors.values():
		roles[a.id] = a.role
		players[a.id] = {"name": a.name, "look": a.look, "alive": a.alive, "bot": a.bot, "out": a.out}
	result = {
		"winner": winner, "reason": reason, "roles": roles, "players": players,
		"chores_done": chores_done, "chores_total": chores_total,
		"lit": lit_count(), "lanterns": lit.size(),
		"time": night_total - night_left,
		"stats": stats.duplicate(),
	}
	net.broadcast("_h_game_over", [result])
	ended.emit(result)
	return true


# --- Sending --------------------------------------------------------------

func _send_snapshots() -> void:
	for viewer in _humans:
		var v: Dictionary = actors[viewer]
		if v.out:
			continue
		var list := []
		for a in actors.values():
			if a.id == viewer or not can_see(v, a):
				continue
			var flags := 0
			if a.ghost:
				flags |= 1
			if v.role == Rules.Role.HOLLOW and a.role == Rules.Role.HOLLOW:
				flags |= 2
			if a.carry != "":
				flags |= 4
			list.append([a.id, snappedf(a.pos.x, 0.01), snappedf(a.pos.z, 0.01), snappedf(a.yaw, 0.01), a.anim, flags])
		var rem := []
		for r in remains:
			if can_see_pos(v, r.pos):
				rem.append([r.id, r.victim, r.pos.x, r.pos.z])
		var fp := PackedFloat32Array()
		if v.role == Rules.Role.WATCHMAN and v.alive:
			for p in prints:
				if p.id != viewer and Vector2(p.x - v.pos.x, p.z - v.pos.z).length() <= Rules.VIEW_RADIUS:
					fp.append_array([p.x, p.z, time - float(p.t)])
		net.send(viewer, "_h_snapshot", [list, rem, fp])


func _send_status() -> void:
	net.broadcast("_h_status", [maxf(night_left, 0.0), chores_done, chores_total, lit_count()])


func _send_lanterns() -> void:
	var bytes := PackedByteArray()
	for on in lit:
		bytes.append(1 if on else 0)
	net.broadcast("_h_lanterns", [bytes])


func _send_private(id: int) -> void:
	if id > 0 and actors.has(id) and not actors[id].bot:
		net.send(id, "_h_you", [_private_state(id)])


func _private_state(id: int) -> Dictionary:
	var a: Dictionary = actors[id]
	var chores := []
	for c in a.chores:
		chores.append([c.key, c.step, c.done])
	return {
		"alive": a.alive, "ghost": a.ghost, "banished": a.banished,
		"chores": chores, "carry": a.carry,
		"snuff_cd": maxf(0.0, a.snuff_ready - time), "take_cd": maxf(0.0, a.take_ready - time),
		"bell_left": a.bell_left, "bell_cd": maxf(0.0, a.bell_ready - time),
		"seer_used": a.seer_used, "flicker_used": a.flicker_used,
	}
