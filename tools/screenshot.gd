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
		elif args[i] in ["title", "lobby", "about", "howto", "practice"]:
			pass
		else:
			times.append(float(args[i]))
	if times.is_empty():
		times = [6.0]
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	LGSettings.set_value("player", "name", "Ken", false)
	if "title" in args or "lobby" in args or "about" in args or "howto" in args:
		get_tree().current_scene = null
		if "lobby" in args:
			Session.start_solo(5)
		LGScenes.change_scene("res://game/ui/%s.tscn" % ("lobby" if "lobby" in args else "title"))
		await get_tree().create_timer(4.0).timeout
		if "about" in args:
			get_tree().current_scene._show_about()
			await get_tree().create_timer(0.5).timeout
		if "howto" in args:
			get_tree().current_scene._show_howto()
			await get_tree().create_timer(0.5).timeout
			var panel: HowToPanel = get_tree().current_scene._ui.get_child(get_tree().current_scene._ui.get_child_count() - 1)
			for page in HowToPanel.pages().size():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s_howto%d.png" % [prefix, page])
				panel._go(1)
				await get_tree().create_timer(0.2).timeout
			get_tree().quit()
			return
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_menu.png" % prefix)
		get_tree().quit()
		return
	# Stay alive when the game scene replaces the current scene.
	get_tree().current_scene = null
	if "practice" in args:
		Session.start_practice()
	else:
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
