class_name Rules
extends RefCounted
## Game rules: roles, actions, distances, timings, chores and house rules.

enum Role { LAMPLIGHTER, HOLLOW, SEER, WATCHMAN }
enum Team { VILLAGE, HOLLOW }
enum Phase { LOADING, NIGHT, MEETING, ENDED }
enum MeetingPhase { DISCUSS, VOTE, REVEAL }
enum Act { RELIGHT_START, RELIGHT_DONE, CHORE_START, CHORE_DONE, SNUFF, TAKE, REPORT, BELL, SEER, FLICKER, CANCEL }
enum Anim { IDLE, WALK, INTERACT, CARRY_IDLE, CARRY_WALK, EMOTE_YES, EMOTE_NO, SIT }

const ROLE_NAMES := {
	Role.LAMPLIGHTER: "Lamplighter",
	Role.HOLLOW: "Hollow",
	Role.SEER: "Seer",
	Role.WATCHMAN: "Watchman",
}
const ROLE_BLURBS := {
	Role.LAMPLIGHTER: "Keep the lanterns lit and finish your chores before dawn. Find the Hollow.",
	Role.HOLLOW: "Snuff the lanterns and take villagers in the dark. Don't get caught.",
	Role.SEER: "Once tonight, look closely at a villager to learn if they are Hollow. Choose well.",
	Role.WATCHMAN: "You see fresh footprints in the dark for a few seconds after someone passes.",
}

const SKIP_VOTE := 0

# Distances (metres)
const PERSONAL_LIGHT := 4.5
const LANTERN_RADIUS := 6.0
const VIEW_RADIUS := 14.0
## Chores need a lit lantern this close to the station (your own lantern is
## too dim to work by), except chores marked "dark".
const WORK_LIGHT_RADIUS := 7.0
const INTERACT_RANGE := 2.3
const TAKE_RANGE := 1.9
const SEER_RANGE := 3.0
const BELL_RANGE := 3.0

# Movement
const WALK_SPEED := 3.6
const BOT_SPEED := 3.1
const GHOST_SPEED := 4.2

# Timings (seconds)
const RELIGHT_TIME := 2.0
const SNUFF_COOLDOWN := 22.0
const TAKE_COOLDOWN := 25.0
const FIRST_COOLDOWN := 12.0
const BELL_COOLDOWN := 15.0
const REVEAL_TIME := 6.0
const FOOTPRINT_LIFE := 6.0
const FLICKER_TIME := 3.0

## Chores: each has one or more stations visited in order, each with a
## minigame. `min` is the shortest time the host accepts for that step.
const CHORES := {
	"water": {"label": "Pump water at the fountain", "steps": [{"station": "fountain", "game": "mash", "min": 1.2}]},
	"fence": {"label": "Mend the broken fence", "steps": [{"station": "fence", "game": "timing", "min": 1.5}]},
	"animals": {"label": "Feed the animals", "steps": [{"station": "pen", "game": "hold", "time": 3.0, "min": 2.5}]},
	"candles": {"label": "Light the chapel candles", "steps": [{"station": "chapel", "game": "sequence", "min": 1.2}]},
	"hay": {"label": "Stack the hay", "steps": [{"station": "hay", "game": "hold", "time": 2.5, "min": 2.0}]},
	"wood": {"label": "Bring wood to the campfire", "steps": [
		{"station": "woodpile", "game": "hold", "time": 1.5, "min": 1.2, "carry": "wood"},
		{"station": "campfire", "game": "hold", "time": 1.0, "min": 0.8}]},
	"market": {"label": "Tidy the market stall", "steps": [{"station": "market", "game": "sequence", "min": 1.2}]},
	"grave": {"label": "Dig at the old grave", "steps": [{"station": "grave", "game": "mash", "min": 1.5, "dark": true}]},
}

## Lobby settings the host can change. Every client gets a copy.
const DEFAULT_SETTINGS := {
	"night_minutes": 8,
	"hollow_count": 0,         # 0 = automatic (1 for up to 6 players, 2 above)
	"special_roles": true,     # Seer from 5 players, Watchman from 7
	"chores_each": 5,
	"discussion_seconds": 45,
	"vote_seconds": 30,
	"reveal_on_banish": true,
	"anonymous_votes": true,
	"bell_uses": 1,
	"dawn_chore_goal": 0.75,   # share of chores needed at dawn for the village
	"dark_fraction": 0.25,     # Hollow win if fewer lanterns than this stay lit
	"ai_brains": true,         # bots think with the local LLM when available
}


static func team_of(role: int) -> int:
	return Team.HOLLOW if role == Role.HOLLOW else Team.VILLAGE


static func hollow_count_for(players: int, setting: int) -> int:
	if setting > 0:
		return clampi(setting, 1, maxi(1, (players - 1) / 2))
	return 1 if players <= 6 else 2


## Deals roles for `ids` (already shuffled by the caller's RNG).
static func deal_roles(ids: Array, settings: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var order := ids.duplicate()
	_shuffle(order, rng)
	var roles := {}
	var n := order.size()
	var hollow := hollow_count_for(n, int(settings.get("hollow_count", 0)))
	var i := 0
	for h in hollow:
		roles[order[i]] = Role.HOLLOW
		i += 1
	if settings.get("special_roles", true):
		if n >= 5 and i < n:
			roles[order[i]] = Role.SEER
			i += 1
		if n >= 7 and i < n:
			roles[order[i]] = Role.WATCHMAN
			i += 1
	while i < n:
		roles[order[i]] = Role.LAMPLIGHTER
		i += 1
	return roles


static func deal_chores(count: int, rng: RandomNumberGenerator) -> Array:
	var keys := CHORES.keys()
	_shuffle(keys, rng)
	return keys.slice(0, clampi(count, 1, keys.size()))


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
