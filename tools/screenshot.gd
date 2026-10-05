extends Node
## Boots a solo night and saves screenshots, for checking the look without a
## screen (run under xvfb-run):
##   godot --path . tools/screenshot.tscn -- out_prefix [seconds...]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "/tmp/shot"
	var times := []
	var meeting := false
	for i in range(1, args.size()):
		if args[i] == "meeting":
			meeting = true
		else:
			times.append(float(args[i]))
	if times.is_empty():
		times = [6.0]
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	LGSettings.set_value("player", "name", "Ken", false)
	# Stay alive when the game scene replaces the current scene.
	get_tree().current_scene = null
	Session.start_solo(5)
	Session.start_match()
	var t := 0.0
	var n := 0
	if meeting:
		await get_tree().create_timer(3.0).timeout
		t = 3.0
		var game: Game = get_tree().current_scene
		game.host.time = 60.0
		game.host._start_meeting(-1, "bell", {})
		await get_tree().process_frame
		var mp := game.hud.meeting
		print("root ", game.hud.root.get_rect(), " meeting ", mp.get_rect(), " panel ", mp._panel.get_rect(), " anchors ", mp.anchor_right, " ", mp.anchor_bottom)
	for when in times:
		await get_tree().create_timer(when - t).timeout
		t = when
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, n])
		n += 1
	get_tree().quit()
