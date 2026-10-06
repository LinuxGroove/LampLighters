class_name BotTalk
extends RefCounted
## What bots say and how they vote in meetings.
##
## With a local language model ready (LGBrain), each speaking bot gets a short
## prompt built from its own memory: what it saw, what it witnessed, and what
## has been said so far. Hollow bots are told to lie. Without a model, or if a
## reply is slow, bots fall back to scripted lines from BotBrain.statement().

const MAX_SPEAKERS := 4
const LLM_TIMEOUT := 12.0

var host: MatchHost
var rng := RandomNumberGenerator.new()
var _queue: Array = []  # {at, id}
var _votes: Array = []  # {at, id}
var _elapsed := 0.0
var _llm_busy := false
var _meeting_serial := 0


func _init(p_host: MatchHost) -> void:
	host = p_host
	rng.seed = host.rng.randi()


func use_llm() -> bool:
	return bool(host.settings.get("ai_brains", true)) and LGBrain.is_ready()


func begin_meeting(m: Dictionary) -> void:
	_meeting_serial += 1
	_elapsed = 0.0
	_queue.clear()
	_votes.clear()
	for bot in host.bots.values():
		bot.before_meeting(m)
	var speakers: Array = []
	for bot in host.bots.values():
		if host.actors[bot.id].alive:
			speakers.append(bot.id)
	BotTalk._shuffle(speakers, rng)
	# The bot who called the meeting speaks first; anyone who knows something
	# important always gets a turn.
	speakers.sort_custom(func(x, y): return _urgency(x, m) > _urgency(y, m))
	var discuss := float(host.settings.discussion_seconds)
	var count := mini(speakers.size(), MAX_SPEAKERS)
	for i in count:
		var at := 1.5 + (discuss - 6.0) * float(i) / float(maxi(count, 1)) + rng.randf_range(0.0, 2.0)
		_queue.append({"at": at, "id": speakers[i]})
	# A second word from the bot with the strongest case, late in the talk.
	if count > 0 and _urgency(speakers[0], m) >= 2:
		_queue.append({"at": discuss - 4.0, "id": speakers[0], "followup": true})
	_queue.sort_custom(func(x, y): return x.at < y.at)


func tick_discussion(delta: float) -> void:
	_elapsed += delta
	while not _queue.is_empty() and _queue[0].at <= _elapsed:
		var q: Dictionary = _queue.pop_front()
		_speak(q.id, q.get("followup", false))


func begin_vote() -> void:
	_elapsed = 0.0
	_queue.clear()
	var window := maxf(3.0, minf(14.0, float(host.settings.vote_seconds) - 3.0))
	for bot in host.bots.values():
		if host.actors[bot.id].alive:
			_votes.append({"at": rng.randf_range(2.0, window), "id": bot.id})
	_votes.sort_custom(func(x, y): return x.at < y.at)


func tick_vote(delta: float) -> void:
	_elapsed += delta
	while not _votes.is_empty() and _votes[0].at <= _elapsed:
		var v: Dictionary = _votes.pop_front()
		if host.bots.has(v.id):
			host.vote(v.id, host.bots[v.id].choose_vote())


func _urgency(id: int, m: Dictionary) -> int:
	var bot: BotBrain = host.bots[id]
	var u := 0
	if m.caller == id:
		u += 3
	for k in bot.known:
		if bot.known[k] == true and host.actors[k].alive:
			u += 2
	if bot.accused_me != 0:
		u += 1
	return u


func _speak(id: int, followup: bool) -> void:
	var a: Dictionary = host.actors.get(id, {})
	if a.is_empty() or not a.alive:
		return
	var bot: BotBrain = host.bots[id]
	if use_llm() and not _llm_busy:
		_speak_llm(bot, followup)
		return
	if followup and bot.accused_me == 0:
		return
	host.say(id, bot.statement())


func _speak_llm(bot: BotBrain, followup: bool) -> void:
	_llm_busy = true
	var serial := _meeting_serial
	var messages := prompt_for(bot, followup)
	var done := {"text": ""}
	var timer := host.get_tree().create_timer(LLM_TIMEOUT)
	var request := func():
		done.text = await LGBrain.chat_async(messages, 120, 0.9, true)
		done["finished"] = true
	request.call()
	while not done.has("finished") and timer.time_left > 0.0:
		await host.get_tree().process_frame
	_llm_busy = false
	if serial != _meeting_serial or host.phase != Rules.Phase.MEETING:
		return
	var reply := LlmClient.extract_json(str(done.text))
	var say := str(reply.get("say", "")).strip_edges()
	if say == "" or say.length() > 220:
		host.say(bot.id, bot.statement())
		return
	var vote_name := str(reply.get("vote", "")).strip_edges().to_lower()
	for o in host.actors.values():
		if str(o.name).to_lower() == vote_name:
			bot.llm_vote = o.id
	# What the bot says out loud is what the room heard, so it decides the
	# vote; the model's "vote" field only counts when the line names nobody.
	var spoken := bot.stance_of(say)
	if spoken != BotBrain.NO_STANCE:
		bot.stance = spoken
		bot.llm_vote = spoken if spoken != Rules.SKIP_VOTE else BotBrain.NO_STANCE
	elif vote_name == "skip" and bot.stance == BotBrain.NO_STANCE:
		bot.stance = Rules.SKIP_VOTE
	host.say(bot.id, say)


## The chat messages for one bot's turn to speak.
func prompt_for(bot: BotBrain, followup := false) -> Array:
	var a := bot.me()
	var m := host.meeting
	var alive := []
	var gone := []
	for o in host.actors.values():
		if o.out:
			continue
		if o.alive:
			alive.append(o.name)
		else:
			gone.append(o.name)
	var role_text := ""
	match a.role:
		Rules.Role.HOLLOW:
			var allies := []
			for o in host.actors.values():
				if o.role == Rules.Role.HOLLOW and o.id != a.id:
					allies.append(o.name)
			role_text = "You are secretly HOLLOW, on the graveyard's side. You put lanterns out and take villagers in the dark. Never admit it. Sound like a helpful villager, deflect suspicion and, if it seems believable, cast doubt on an innocent villager."
			if not allies.is_empty():
				role_text += " Your fellow Hollow: %s. Never vote for them or accuse them." % ", ".join(allies)
		Rules.Role.SEER:
			role_text = "You are the SEER, on the village's side. Share what you learned from looking closely at people."
		Rules.Role.WATCHMAN:
			role_text = "You are the WATCHMAN, on the village's side. You can see fresh footprints in the dark."
		_:
			role_text = "You are a LAMPLIGHTER, on the village's side. Find the Hollow."
	var system := "You are %s, a villager in Graveyard Hollow, a cozy, spooky social deduction game. At night the village keeps its lanterns lit while one or two secret Hollow snuff them and take villagers in the dark. Now everyone has gathered at the bell to talk, then vote someone out. %s\nSpeak in the first person, casually, like a person at a party game. One or two short sentences, under 30 words. Only mention facts from your memory below; never invent sightings. Never mention being an AI or a game.\nYour vote must match what you say: if you accuse someone, vote for them; if you say you're unsure, vote skip. Only change your vote if you say why.\nReply as JSON: {\"say\": \"what you say out loud\", \"vote\": \"a name, or skip\"}." % [a.name, role_text]
	var facts := []
	for mem in bot.memory.slice(maxi(0, bot.memory.size() - 12)):
		facts.append("- " + str(mem.text))
	if facts.is_empty():
		facts.append("- You didn't notice anything unusual.")
	var why := ""
	if m.reason == "report":
		why = "%s called this meeting after finding %s's empty lantern near %s." % [
			host.actors[m.caller].name, host.actors[m.victim].name, m.place]
	else:
		why = "%s rang the bell to call this meeting." % host.actors[m.caller].name
	var said := []
	for line in m.log.slice(maxi(0, m.log.size() - 8)):
		said.append("%s: \"%s\"" % [host.actors[line.id].name, line.text])
	var earlier := ""
	if bot.stance == Rules.SKIP_VOTE:
		earlier = "\nEarlier in this meeting you said you'd rather skip."
	elif bot.stance != BotBrain.NO_STANCE:
		earlier = "\nEarlier in this meeting you said you'd vote for %s." % host.actors[bot.stance].name
	var user := "%s\nStill in the village: %s.\nAlready taken or banished: %s.\nYour memory of tonight:\n%s\nSo far in this meeting:\n%s%s\n%s" % [
		why,
		", ".join(alive),
		", ".join(gone) if not gone.is_empty() else "nobody",
		"\n".join(facts),
		"\n".join(said) if not said.is_empty() else "(nobody has spoken yet)",
		earlier,
		"Add one more thing, responding to what others said." if followup else "Your turn to speak.",
	]
	return [{"role": "system", "content": system}, {"role": "user", "content": user}]


static func _shuffle(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
