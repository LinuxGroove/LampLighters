class_name Hints
extends Node
## One-time tips that appear the first time something comes up during a match,
## such as the first dark lantern or the first body. What has been shown is
## remembered between games, and Settings can turn the tips off.

const CHECK_EVERY := 0.5
const MAP_HINT_AFTER := 40.0
const DAWN_HINT_AT := 90.0

var game: Game
var hud: Hud

var _seen := {}
var _check_t := 0.0
var _clock := 0.0


func setup(p_game: Game, p_hud: Hud) -> void:
	game = p_game
	hud = p_hud
	for key in str(LGSettings.get_value("tutorial", "seen", "")).split(",", false):
		_seen[key] = true


func _process(delta: float) -> void:
	if game.phase != Rules.Phase.NIGHT or game.player == null or hud.blocks_input():
		return
	_clock += delta
	_check_t += delta
	if _check_t < CHECK_EVERY:
		return
	_check_t = 0.0
	if not bool(LGSettings.get_value("tutorial", "hints", true)):
		return
	var village_side: bool = Rules.team_of(game.role) == Rules.Team.VILLAGE
	if not game.visible_remains.is_empty():
		_once("body", "You found someone who was taken. Report them to call a meeting.", "interact")
	elif village_side and game.lit.has(false):
		_once("dark_lantern", "A lantern went dark. Hold to relight it.", "interact")
	elif not game.player.special.is_empty() and not game.is_ghost():
		_once("special_%d" % game.role, str(game.player.special.text), "special")
	elif _clock >= MAP_HINT_AFTER:
		_once("map", "Open the map to see the lanterns and your chores.", "show_map")
	elif game.night_left <= DAWN_HINT_AT and game.night_left > 0.0:
		_once("dawn", "Dawn is close. Finish your chores!" if village_side else "Dawn is close. Keep the village from finishing its chores.")
	elif village_side and _lanterns_low():
		_once("low_light", "The village is nearly dark. Relight the lanterns before the Hollow win.")


func _lanterns_low() -> bool:
	var needed := int(ceil(game.lit.size() * float(game.settings.get("dark_fraction", 0.25))))
	return game.lit.count(true) <= needed + 2


func _once(key: String, text: String, action := "") -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	LGSettings.set_value("tutorial", "seen", ",".join(_seen.keys()))
	hud.show_hint(text, action)
