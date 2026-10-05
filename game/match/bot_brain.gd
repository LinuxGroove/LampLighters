class_name BotBrain
extends RefCounted
## One bot player, driven on the host with the same rules people play by.
##
## Bots only know what their own character could see: they remember who they
## saw where, what they witnessed in the dark, and what was said in meetings.
## BotTalk turns that memory into meeting statements and votes.

const MEMORY_SIZE := 40
const LOOK_EVERY := 0.5

var host: MatchHost
var id: int
var rng := RandomNumberGenerator.new()
## Remembered facts in plain words, newest last: {t, text}
var memory: Array = []
## id -> {t, place, pos}: where this bot last saw each actor
var seen := {}
## id -> how strongly this bot suspects them
var suspicion := {}
## id -> true (Hollow) or false (cleared), from looking closely or witnessing
var known := {}
var taken_by := 0
var accused_me := 0
## Set by an LLM reply; used when voting if still sensible.
var llm_vote := -1

var _goal := {}
var _path := PackedVector3Array()
var _path_i := 0
var _busy_until := 0.0
var _think_t := 0.0
var _look_t := 0.0
var _idle_until := 0.0
var _last_place := {}


func _init(p_host: MatchHost, p_id: int) -> void:
	host = p_host
	id = p_id
	rng.seed = host.rng.randi() ^ (p_id * 7919)


func me() -> Dictionary:
	return host.actors[id]


func tick(delta: float) -> void:
	var a := me()
	if a.out:
		return
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = LOOK_EVERY
		# Someone busy with a chore isn't watching the street.
		if a.action.is_empty():
			_look(a)
	if not a.action.is_empty():
		a.anim = Rules.Anim.INTERACT
		if host.time >= _busy_until:
			_finish_action(a)
		return
	_think_t -= delta
	if _think_t <= 0.0 or _goal.is_empty():
		_think_t = rng.randf_range(0.4, 0.9)
		_think(a)
	_move(a, delta)


# --- Perception and memory -------------------------------------------------

func _look(a: Dictionary) -> void:
	for o in host.actors.values():
		if o.id == id or o.out or not host.can_see(a, o):
			continue
		var place := host.village.landmark_name(o.pos)
		seen[o.id] = {"t": host.time, "place": place, "pos": o.pos}
		if a.alive and not o.ghost and _last_place.get(o.id, "") != place:
			_last_place[o.id] = place
			remember("Saw %s near %s." % [o.name, place])


func remember(text: String) -> void:
	memory.append({"t": host.time, "text": text})
	if memory.size() > MEMORY_SIZE:
		memory.pop_front()


func add_suspicion(who: int, amount: float) -> void:
	if who == id or not host.actors.has(who):
		return
	suspicion[who] = float(suspicion.get(who, 0.0)) + amount


func witness(who: int, what: String, data: Dictionary) -> void:
	var w: Dictionary = host.actors[who]
	var place := host.village.landmark_name(w.pos)
	match what:
		"take":
			var v: Dictionary = host.actors[data.victim]
			known[who] = true
			add_suspicion(who, 200.0)
			remember("I SAW %s take %s near %s!" % [w.name, v.name, place])
		"snuff":
			add_suspicion(who, 120.0)
			remember("I saw %s put out the lantern near %s." % [w.name, place])
		"relit":
			add_suspicion(who, -8.0)


func notice_flicker(lantern: int) -> void:
	var a := me()
	if not a.alive:
		return
	var lpos: Vector3 = host.lantern_pos[lantern]
	if host._flat_dist(a.pos, lpos) > Rules.VIEW_RADIUS * 1.5:
		return
	var place := host.village.landmark_name(lpos)
	var near := []
	for o in host.actors.values():
		if o.alive and not o.out and o.id != id and host._flat_dist(o.pos, lpos) <= Rules.LANTERN_RADIUS + 1.0:
			near.append(o.name)
			add_suspicion(o.id, 25.0)
	if near.is_empty():
		remember("The lantern near %s flickered, but nobody was there." % place)
	else:
		remember("The lantern near %s flickered next to %s." % [place, ", ".join(near)])


func learn_seer(target: int, hollow: bool) -> void:
	known[target] = hollow
	add_suspicion(target, 300.0 if hollow else -100.0)
	var n: String = host.actors[target].name
	remember("I looked closely at %s: %s" % [n, "they ARE Hollow!" if hollow else "they are not Hollow."])


func learn_taken(by: int) -> void:
	taken_by = by
	_goal = {}


func hear(speaker: int, text: String) -> void:
	if speaker == id:
		return
	var low := text.to_lower()
	var accusing := ["suspect", "hollow", "saw", "took", "vote", "don't trust", "lying", "sus"].any(func(w): return low.contains(w))
	var clearing := ["trust", "was with", "innocent", "not hollow", "cleared"].any(func(w): return low.contains(w)) and not low.contains("don't trust")
	var weight := 1.0
	if known.get(speaker, false) == true:
		weight = -1.0
	elif suspicion.get(speaker, 0.0) > 60.0:
		weight = 0.3
	for o in host.actors.values():
		if o.id == speaker or not low.contains(str(o.name).to_lower()):
			continue
		if o.id == id:
			if accusing:
				accused_me = speaker
				add_suspicion(speaker, 10.0)
			continue
		if clearing:
			add_suspicion(o.id, -5.0 * weight)
		elif accusing:
			add_suspicion(o.id, 6.0 * weight)


func learn_result(res: Dictionary) -> void:
	var b: int = res.banished
	if b == Rules.SKIP_VOTE:
		remember("Nobody was banished at the last meeting.")
		return
	var n: String = host.actors[b].name
	if res.has("role"):
		var hollow: bool = res.role == Rules.Role.HOLLOW
		known[b] = hollow
		remember("%s was banished and %s." % [n, "WAS Hollow" if hollow else "was NOT Hollow"])
	else:
		remember("%s was banished." % n)


## Called when a meeting starts: weigh who was seen near the remains.
func before_meeting(m: Dictionary) -> void:
	var a := me()
	_goal = {}
	_path = PackedVector3Array()
	if m.victim == 0 or not a.alive:
		return
	var place: String = m.place
	for other_id in seen:
		var s: Dictionary = seen[other_id]
		if other_id != m.victim and s.place == place and host.time - float(s.t) < 20.0:
			add_suspicion(other_id, 12.0)
			remember("I saw %s near %s not long before %s was found." % [host.actors[other_id].name, place, host.actors[m.victim].name])


func after_meeting() -> void:
	_goal = {}
	_path = PackedVector3Array()
	llm_vote = -1
	accused_me = 0
	_idle_until = host.time + rng.randf_range(0.0, 1.5)


# --- Deciding -------------------------------------------------------------

func _think(a: Dictionary) -> void:
	if host.time < _idle_until:
		return
	var want := {}
	if a.role == Rules.Role.HOLLOW:
		want = _think_hollow(a) if a.alive else _wander_goal(a)
	elif a.ghost:
		want = _think_ghost(a)
	else:
		want = _think_villager(a)
	if want.is_empty():
		want = _wander_goal(a)
	if not _goal.is_empty() and want.kind == _goal.kind and want.get("target", -1) == _goal.get("target", -1):
		return
	_set_goal(a, want)


func _think_villager(a: Dictionary) -> Dictionary:
	for r in host.remains:
		if host.can_see_pos(a, r.pos):
			return {"kind": "report", "target": r.id, "pos": r.pos, "reach": Rules.INTERACT_RANGE - 0.4}
	# Ring the bell on a certain Hollow, or someone seen snuffing a lantern.
	if a.bell_left > 0 and host.time >= a.bell_ready:
		var top := _top_suspect()
		var sure := false
		for k in known:
			if known[k] == true and host.actors[k].alive:
				sure = true
		if sure or (top != 0 and float(suspicion[top]) >= 100.0):
			return {"kind": "bell", "target": 0, "pos": host.village.bell_position(), "reach": Rules.BELL_RANGE - 0.6}
	if a.role == Rules.Role.SEER and not a.seer_used and host.time > 40.0:
		var pick := _seer_pick(a)
		if pick != 0:
			return {"kind": "seer", "target": pick, "follow": pick, "pos": host.actors[pick].pos, "reach": Rules.SEER_RANGE - 0.6}
	var lantern := _unlit_lantern(a, 9.0)
	if lantern >= 0:
		return {"kind": "relight", "target": lantern, "pos": host.lantern_pos[lantern], "reach": Rules.INTERACT_RANGE - 0.5}
	var chore := _chore_goal(a)
	if not chore.is_empty():
		return chore
	lantern = _unlit_lantern(a, INF)
	if lantern >= 0:
		return {"kind": "relight", "target": lantern, "pos": host.lantern_pos[lantern], "reach": Rules.INTERACT_RANGE - 0.5}
	return {}


func _think_ghost(a: Dictionary) -> Dictionary:
	if not a.flicker_used and taken_by != 0:
		var k: Dictionary = host.actors[taken_by]
		if k.alive and not k.out:
			for i in host.lit.size():
				if host.lit[i] and host._flat_dist(host.lantern_pos[i], k.pos) <= Rules.LANTERN_RADIUS \
						and host._flat_dist(host.lantern_pos[i], a.pos) <= 20.0:
					return {"kind": "flicker", "target": i, "pos": host.lantern_pos[i], "reach": Rules.INTERACT_RANGE}
	return _chore_goal(a)


func _think_hollow(a: Dictionary) -> Dictionary:
	# Keep at it once a take is under way.
	if _goal.get("kind", "") == "take" and _victim_ok(a, host.actors[_goal.target]):
		return _goal
	if host.time >= a.take_ready and rng.randf() < 0.85:
		var victim := _pick_victim(a)
		if victim != 0:
			return {"kind": "take", "target": victim, "follow": victim, "pos": host.actors[victim].pos, "reach": Rules.TAKE_RANGE - 0.5}
	# Wait in the dark by a lantern just snuffed: whoever comes to relight it
	# is alone in the dark.
	if _goal.get("kind", "") == "lurk" and host.time < float(_goal.until):
		return _goal
	if host.time >= a.snuff_ready:
		var lantern := _safe_lantern_to_snuff(a)
		if lantern >= 0:
			return {"kind": "snuff", "target": lantern, "pos": host.lantern_pos[lantern], "reach": Rules.INTERACT_RANGE - 0.5}
	if _goal.get("kind", "") in ["fake", "wander"]:
		return _goal
	var chore := _chore_goal(a)
	if not chore.is_empty():
		chore.kind = "fake"
		return chore
	return {}


func _chore_goal(a: Dictionary) -> Dictionary:
	for i in a.chores.size():
		var c: Dictionary = a.chores[i]
		if c.done:
			continue
		var pos := host._station_pos(a, i)
		if pos == Vector3.INF:
			continue
		if not host._chore_step(a, i).get("dark", false) and not host.work_lit(pos):
			# Can't work in the dark: relight a lantern by the station first.
			if a.ghost:
				continue
			var lantern := _unlit_lantern_near(pos, Rules.WORK_LIGHT_RADIUS)
			if lantern < 0:
				continue
			return {"kind": "relight", "target": lantern, "pos": host.lantern_pos[lantern], "reach": Rules.INTERACT_RANGE - 0.5}
		return {"kind": "chore", "target": i, "pos": pos, "reach": Rules.INTERACT_RANGE - 0.5}
	return {}


func _unlit_lantern_near(pos: Vector3, within: float) -> int:
	var best := -1
	var best_d := within
	for i in host.lit.size():
		var d := host._flat_dist(pos, host.lantern_pos[i])
		if not host.lit[i] and d <= best_d:
			best = i
			best_d = d
	return best


func _wander_goal(a: Dictionary) -> Dictionary:
	var marks := host.village.landmark_positions().values()
	var pos: Vector3 = marks[rng.randi_range(0, marks.size() - 1)] if not marks.is_empty() else Vector3.ZERO
	pos += Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
	return {"kind": "wander", "target": rng.randi(), "pos": pos, "reach": 1.5}


## Somewhere well away from here, to be seen at instead.
func _flee_goal(a: Dictionary) -> Dictionary:
	var best := _wander_goal(a)
	for i in 4:
		var g := _wander_goal(a)
		if host._flat_dist(g.pos, a.pos) > host._flat_dist(best.pos, a.pos):
			best = g
	return best


func _unlit_lantern(a: Dictionary, within: float) -> int:
	var best := -1
	var best_d := within
	for i in host.lit.size():
		if host.lit[i]:
			continue
		var d := host._flat_dist(a.pos, host.lantern_pos[i])
		if d < best_d and not _someone_relighting(i):
			best = i
			best_d = d
	return best


func _someone_relighting(i: int) -> bool:
	for o in host.actors.values():
		if o.id != id and not o.action.is_empty() and o.action.kind == Rules.Act.RELIGHT_START and o.action.target == i:
			return true
	return false


func _seer_pick(a: Dictionary) -> int:
	var best := 0
	var best_s := -INF
	for o in host.actors.values():
		if o.id == id or not o.alive or o.out or known.has(o.id):
			continue
		if not host.can_see(a, o) or host._flat_dist(a.pos, o.pos) > 10.0:
			continue
		var s := float(suspicion.get(o.id, 0.0)) + rng.randf_range(0.0, 10.0)
		if s > best_s:
			best = o.id
			best_s = s
	return best


func _pick_victim(a: Dictionary) -> int:
	var best := 0
	var best_d := 16.0
	for o in host.actors.values():
		var d := host._flat_dist(a.pos, o.pos)
		if d <= best_d and _victim_ok(a, o):
			best = o.id
			best_d = d
	return best


func _victim_ok(a: Dictionary, v: Dictionary) -> bool:
	if not v.alive or v.out or v.role == Rules.Role.HOLLOW or not host.can_see(a, v):
		return false
	if host.lit_at(v.pos):
		return false
	# Nobody else may be close enough to see it happen.
	for w in host.actors.values():
		if w.id == v.id or w.id == id or not w.alive or w.out or w.role == Rules.Role.HOLLOW:
			continue
		if host._flat_dist(w.pos, v.pos) <= Rules.PERSONAL_LIGHT + 1.0 or host.can_see(w, a):
			return false
	return true


func _safe_lantern_to_snuff(a: Dictionary) -> int:
	var best := -1
	var best_d := 22.0
	var stations: Array = host.village.stations().values()
	for i in host.lit.size():
		if not host.lit[i]:
			continue
		var d := host._flat_dist(a.pos, host.lantern_pos[i])
		# Lanterns that light a chore station hurt the village most.
		for s in stations:
			if host._flat_dist((s as Node3D).global_position, host.lantern_pos[i]) <= Rules.WORK_LIGHT_RADIUS:
				d -= 6.0
				break
		if d >= best_d:
			continue
		var watched := false
		for w in host.actors.values():
			if w.alive and not w.out and w.role != Rules.Role.HOLLOW \
					and host._flat_dist(w.pos, host.lantern_pos[i]) <= Rules.VIEW_RADIUS:
				watched = true
				break
		if not watched:
			best = i
			best_d = d
	return best


# --- Acting ---------------------------------------------------------------

func _set_goal(a: Dictionary, goal: Dictionary) -> void:
	_goal = goal
	_repath(a)


func _repath(a: Dictionary) -> void:
	if a.ghost:
		_path = PackedVector3Array([_goal.pos])
	else:
		_path = host.village.find_path(a.pos, _goal.pos)
	_path_i = 0


func _move(a: Dictionary, delta: float) -> void:
	if _goal.is_empty():
		a.anim = Rules.Anim.IDLE
		return
	if _goal.has("follow"):
		var f: Dictionary = host.actors[_goal.follow]
		if host._flat_dist(f.pos, _goal.pos) > 1.2:
			_goal.pos = f.pos
			_repath(a)
	if host._flat_dist(a.pos, _goal.pos) <= float(_goal.reach):
		_arrive(a)
		return
	if _path_i >= _path.size():
		_repath(a)
		if _path.is_empty():
			_goal = {}
			return
	var target: Vector3 = _path[_path_i]
	var to := target - (a.pos as Vector3)
	to.y = 0.0
	var speed := Rules.GHOST_SPEED if a.ghost else Rules.BOT_SPEED
	var step := speed * delta
	if to.length() <= step:
		a.pos = target
		_path_i += 1
	else:
		a.pos += to.normalized() * step
	if to.length() > 0.01:
		a.yaw = lerp_angle(a.yaw, atan2(to.x, to.z), minf(1.0, delta * 10.0))
	a.anim = Rules.Anim.WALK


func _arrive(a: Dictionary) -> void:
	var g := _goal
	a.anim = Rules.Anim.IDLE
	match g.kind:
		"report":
			host.act(id, Rules.Act.REPORT, g.target)
			_goal = {}
		"bell":
			host.act(id, Rules.Act.BELL, 0)
			_goal = {}
		"relight":
			_goal = {}
			if host.act(id, Rules.Act.RELIGHT_START, g.target):
				_busy_until = host.time + Rules.RELIGHT_TIME + rng.randf_range(0.1, 0.5)
		"chore", "fake":
			_goal = {}
			if host.act(id, Rules.Act.CHORE_START, g.target):
				var step := host._chore_step(a, g.target)
				var t := float(step.get("time", step.get("min", 1.0)))
				_busy_until = host.time + maxf(t, float(step.get("min", 1.0))) + rng.randf_range(0.5, 2.5)
		"snuff":
			if host.act(id, Rules.Act.SNUFF, g.target) and host.time + 4.0 >= a.take_ready:
				var away: Vector3 = (a.pos - host.lantern_pos[g.target]).normalized()
				if away.length() < 0.1:
					away = Vector3(1, 0, 0)
				var spot: Vector3 = host.lantern_pos[g.target] + away.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0)) * 4.0
				_goal = {"kind": "lurk", "target": g.target, "pos": spot, "reach": 1.0, "until": host.time + rng.randf_range(12.0, 20.0)}
			else:
				_goal = _wander_goal(a)
			_repath(a)
		"take":
			if host.act(id, Rules.Act.TAKE, g.target):
				_goal = _flee_goal(a)
				_repath(a)
		"seer":
			host.act(id, Rules.Act.SEER, g.target)
			_goal = {}
		"flicker":
			host.act(id, Rules.Act.FLICKER, g.target)
			_goal = {}
		"wander":
			_goal = {}
			_idle_until = host.time + rng.randf_range(1.5, 4.0)
		"lurk":
			a.anim = Rules.Anim.IDLE


func _finish_action(a: Dictionary) -> void:
	var act: Dictionary = a.action
	match act.kind:
		Rules.Act.RELIGHT_START:
			host.act(id, Rules.Act.RELIGHT_DONE, act.target)
		Rules.Act.CHORE_START:
			host.act(id, Rules.Act.CHORE_DONE, act.target)
		_:
			host.act(id, Rules.Act.CANCEL, 0)
	a.anim = Rules.Anim.IDLE
	_goal = {}
	_idle_until = host.time + rng.randf_range(0.5, 3.0)


# --- Meetings -------------------------------------------------------------

## The player this bot most wants banished, or SKIP_VOTE.
func choose_vote() -> int:
	var a := me()
	var alive := host._voters()
	if a.role == Rules.Role.HOLLOW:
		return _hollow_vote(alive)
	for k in known:
		if known[k] == true and k in alive:
			return k
	if llm_vote > 0 and llm_vote in alive and llm_vote != id and known.get(llm_vote, true) != false:
		return llm_vote
	var best := Rules.SKIP_VOTE
	var best_s := 36.0
	for o in alive:
		if o == id:
			continue
		var s := float(suspicion.get(o, 0.0)) + rng.randf_range(-12.0, 12.0)
		if s > best_s:
			best = o
			best_s = s
	return best


func _hollow_vote(alive: Array) -> int:
	if llm_vote > 0 and llm_vote in alive and host.actors[llm_vote].role != Rules.Role.HOLLOW:
		return llm_vote
	# Go along with whoever the village seems to suspect, as long as it isn't a friend.
	var counts := {}
	for line in host.meeting.get("log", []):
		var low := str(line.text).to_lower()
		for o in alive:
			var oa: Dictionary = host.actors[o]
			if oa.role != Rules.Role.HOLLOW and line.id != o and low.contains(str(oa.name).to_lower()):
				counts[o] = int(counts.get(o, 0)) + 1
	var best := Rules.SKIP_VOTE
	var best_n := 0
	for o in counts:
		if counts[o] > best_n:
			best = o
			best_n = counts[o]
	if best == Rules.SKIP_VOTE and accused_me != 0 and accused_me in alive and host.actors[accused_me].role != Rules.Role.HOLLOW:
		best = accused_me
	return best


## A short scripted statement when no language model is available.
func statement() -> String:
	var a := me()
	var m := host.meeting
	var name_of := func(i: int) -> String: return str(host.actors[i].name)
	if a.role == Rules.Role.HOLLOW:
		return _hollow_statement(a, m, name_of)
	var lines := []
	if m.caller == id and m.reason == "report":
		lines.append("I found %s's lantern near %s." % [name_of.call(m.victim), m.place])
	elif m.caller == id:
		lines.append("I rang the bell.")
	for k in known:
		if host.actors[k].alive and known[k] == true:
			if a.role == Rules.Role.SEER:
				lines.append("I looked closely at %s. They're Hollow!" % name_of.call(k))
			else:
				lines.append("I saw %s do it with my own eyes. Vote %s!" % [name_of.call(k), name_of.call(k)])
			return " ".join(lines)
	var top := _top_suspect()
	if top != 0 and float(suspicion[top]) >= 28.0:
		var where: String = seen.get(top, {}).get("place", "the dark")
		lines.append(["I don't trust %s. They were hanging around %s." % [name_of.call(top), where],
			"%s was near %s right before. Bit odd." % [name_of.call(top), where],
			"Has anyone else been watching %s? I have." % name_of.call(top)][rng.randi_range(0, 2)])
	elif lines.is_empty():
		var place := host.village.landmark_name(a.pos) if seen.is_empty() else _my_recent_place()
		lines.append(["I was doing chores near %s. Didn't see anything." % place,
			"Nothing from me. I was busy near %s." % place,
			"I don't know enough yet. Maybe skip?"][rng.randi_range(0, 2)])
	return " ".join(lines)


func _hollow_statement(a: Dictionary, m: Dictionary, name_of: Callable) -> String:
	var place := _my_recent_place()
	if accused_me != 0 and host.actors[accused_me].alive:
		# Sometimes fight a Seer claim with one of their own.
		if rng.randf() < 0.45:
			return "No. I'm the Seer, and I looked closely at %s. THEY are Hollow!" % name_of.call(accused_me)
		return ["That's not true. I was near %s doing my chores." % place,
			"Why me? %s is just trying to throw you off." % name_of.call(accused_me)][rng.randi_range(0, 1)]
	if m.caller == id and m.reason == "report":
		return "I found %s's lantern near %s. I didn't see who did it." % [name_of.call(m.victim), m.place]
	var scapegoat := 0
	for o in host._voters():
		if host.actors[o].role != Rules.Role.HOLLOW and o != id and seen.has(o):
			scapegoat = o
			break
	if scapegoat != 0 and rng.randf() < 0.6:
		return "I saw %s near %s, wandering about in the dark." % [name_of.call(scapegoat), seen[scapegoat].place]
	return ["I was fixing things near %s. Didn't see anything." % place,
		"No idea. Let's not banish someone innocent.",
		"I've been near %s most of the night." % place][rng.randi_range(0, 2)]


func _top_suspect() -> int:
	var best := 0
	var best_s := -INF
	for o in host._voters():
		if o != id and suspicion.has(o) and float(suspicion[o]) > best_s:
			best = o
			best_s = suspicion[o]
	return best


func _my_recent_place() -> String:
	var a := me()
	for i in range(a.chores.size() - 1, -1, -1):
		if a.chores[i].done or a.chores[i].step > 0:
			return host.village.landmark_name(host.station_position(Rules.CHORES[a.chores[i].key].steps[0].station))
	return host.village.landmark_name(a.pos)
