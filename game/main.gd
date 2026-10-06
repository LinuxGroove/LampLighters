extends Node
## Boots the game: input map, theme and window, then the title screen.
##
## Developer shortcuts (after `--`):
##   --solo        skip the menus and start a night with bots
##   --windowed    don't go fullscreen

func _ready() -> void:
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS, float(LGSettings.get_value("input", "stick_deadzone")))
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	get_window().title = "Graveyard Hollow"
	if str(LGSettings.get_value("player", "name")).strip_edges() == "" and "--solo" in OS.get_cmdline_user_args():
		LGSettings.set_value("player", "name", "Tester", false)
	if "--solo" in OS.get_cmdline_user_args():
		Session.start_solo(5)
		Session.start_match()
		return
	LGScenes.change_scene("res://game/ui/title.tscn")
