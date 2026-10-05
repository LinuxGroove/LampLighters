extends SceneTree
## Renders a scene to PNG for layout checks (needs a display, e.g. xvfb-run).
##   godot --path . -s tools/preview_scene.gd -- out.png res://scene.tscn day|night [x z height]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var scene: PackedScene = load(args[1])
	var mode := args[2] if args.size() > 2 else "day"
	var node: Node3D = scene.instantiate()
	get_root().add_child(node)
	var cam := Camera3D.new()
	if args.size() > 5:
		var target := Vector3(float(args[3]), 0, float(args[4]))
		var h := float(args[5])
		cam.fov = 50
		get_root().add_child(cam)
		cam.look_at_from_position(target + Vector3(0, h, h * 0.68), target)
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 64
		get_root().add_child(cam)
		cam.look_at_from_position(Vector3(0, 60, 0.01), Vector3.ZERO)
	cam.current = true
	if mode == "day":
		var env := node.get_node("Night") as WorldEnvironment
		env.environment.ambient_light_energy = 0.9
		env.environment.ambient_light_color = Color.WHITE
		env.environment.fog_enabled = false
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-60, 30, 0)
		sun.light_energy = 1.2
		get_root().add_child(sun)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out)
	quit()
