class_name LookPreview
extends SubViewportContainer
## A small turning view of a villager look, so players can see what they'll
## look like while they pick one in the lobby.

const TURN_SPEED := 0.6

var _rig: RigCharacter
var _pivot: Node3D
var _look := -1


static func make(look: int, size := Vector2(200, 240)) -> LookPreview:
	var p := LookPreview.new()
	p.custom_minimum_size = size
	p.stretch = true
	p.set_look(look)
	return p


func _init() -> void:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.1)
	cam.fov = 40.0
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.8, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(-1.2, 1.4, 1.4)
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.6
	lamp.omni_range = 5.0
	vp.add_child(lamp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.8)
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)
	_pivot = Node3D.new()
	vp.add_child(_pivot)


func set_look(look: int) -> void:
	if look == _look:
		return
	_look = look
	if _rig:
		_rig.set_model(GameConfig.look_scene(look), Avatar.MODEL_SCALE)
	else:
		_rig = RigCharacter.create(GameConfig.look_scene(look), Avatar.MODEL_SCALE)
		_pivot.add_child(_rig)
	_rig.play("idle")


func _process(delta: float) -> void:
	_pivot.rotation.y = wrapf(_pivot.rotation.y + TURN_SPEED * delta, -PI, PI)
