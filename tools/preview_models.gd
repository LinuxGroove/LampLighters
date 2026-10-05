extends SceneTree
## Renders a row of models to a PNG for checking piece geometry.
## godot --path . -s tools/preview_models.gd -- out.png scale path1 path2 ...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var s := float(args[1])
	var root := Node3D.new()
	var x := 0.0
	for i in range(2, args.size()):
		var scene: PackedScene = load(args[i])
		var n: Node3D = scene.instantiate()
		n.scale = Vector3.ONE * s
		n.position = Vector3(x, 0, 0)
		root.add_child(n)
		var lbl := Label3D.new()
		lbl.text = args[i].get_file().get_basename()
		lbl.position = Vector3(x, -0.3, 1.2)
		lbl.pixel_size = 0.004
		lbl.rotation_degrees.x = -45
		root.add_child(lbl)
		x += 3.0
	var cam := Camera3D.new()
	cam.position = Vector3(x / 2.0 - 1.5, 6, 7)
	cam.look_at_from_position(cam.position, Vector3(x / 2.0 - 1.5, 0.5, 0))
	cam.fov = 60
	root.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.35, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	get_root().add_child(root)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
