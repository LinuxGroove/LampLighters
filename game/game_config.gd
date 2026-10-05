class_name GameConfig
extends RefCounted
## Game-wide constants: identity, version, input map and character looks.

const GAME_ID := "lantern-out"
## Bump PROTOCOL whenever network messages change; mismatched builds are told
## to update instead of desyncing.
const PROTOCOL := 1
const MAX_PLAYERS := 10
const MIN_PLAYERS := 4

const LOOKS := [
	"character-female-a", "character-male-a", "character-female-b", "character-male-b",
	"character-female-c", "character-male-c", "character-female-d", "character-male-d",
	"character-female-e", "character-male-e", "character-female-f", "character-male-f",
]
## A colour per look, used for name tags, map markers and meeting cards.
const LOOK_COLORS := [
	Color("e8635a"), Color("4fa3e0"), Color("f2b53c"), Color("63c06b"),
	Color("b67ae0"), Color("f08a3c"), Color("5fd0c8"), Color("e078b4"),
	Color("c9d65a"), Color("8f9be8"), Color("d0a070"), Color("9ad0f0"),
]

const BOT_NAMES := [
	"Ada", "Bram", "Clem", "Dot", "Edda", "Fenn", "Gus", "Hettie", "Ivo", "Juno",
	"Kit", "Lark", "Mabel", "Ned", "Odile", "Pip", "Quill", "Rosa", "Sol", "Tamsin",
]

## Every action, with keyboard and controller bindings (see LGInput).
const ACTIONS := {
	"move_left": ["key:A", "key:Left", "axis:lx-"],
	"move_right": ["key:D", "key:Right", "axis:lx+"],
	"move_up": ["key:W", "key:Up", "axis:ly-"],
	"move_down": ["key:S", "key:Down", "axis:ly+"],
	"interact": ["key:E", "key:Space", "key:Enter", "joy:a"],
	"cancel": ["key:Escape", "key:Backspace", "joy:b"],
	"special": ["key:Q", "key:F", "joy:x"],
	"ring_bell": ["key:R", "joy:y"],
	"emote_1": ["key:1", "joy:up"],
	"emote_2": ["key:2", "joy:right"],
	"emote_3": ["key:3", "joy:down"],
	"emote_4": ["key:4", "joy:left"],
	"show_map": ["key:Tab", "key:M", "joy:back"],
	"pause": ["key:Escape", "joy:start"],
	"chore_up": ["key:W", "key:Up", "joy:up"],
	"chore_down": ["key:S", "key:Down", "joy:down"],
	"chore_left": ["key:A", "key:Left", "joy:left"],
	"chore_right": ["key:D", "key:Right", "joy:right"],
}


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func look_scene(look: int) -> PackedScene:
	var name: String = LOOKS[clampi(look, 0, LOOKS.size() - 1)]
	return load("res://assets/kenney/mini-characters/%s.glb" % name)


static func look_color(look: int) -> Color:
	return LOOK_COLORS[clampi(look, 0, LOOK_COLORS.size() - 1)]
