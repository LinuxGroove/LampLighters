class_name MenuBackdrop
extends Node3D
## The village at night behind the menus, seen from a slowly circling camera.

const MAP := "res://game/world/moonpatch_village.tscn"

var _cam: Camera3D
var _t := 0.0


func _ready() -> void:
	var village: Node3D = (load(MAP) as PackedScene).instantiate()
	add_child(village)
	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_cam.current = true
	# Light a few lanterns' worth of warmth near the square for the shot.
	var warm := OmniLight3D.new()
	warm.position = Vector3(0, 3, 0)
	warm.omni_range = 9
	warm.light_color = Color(1.0, 0.7, 0.4)
	warm.light_energy = 1.2
	add_child(warm)
	_t = randf() * TAU
	_place()


func _process(delta: float) -> void:
	_t += delta * 0.04
	_place()


func _place() -> void:
	var r := 20.0
	_cam.position = Vector3(cos(_t) * r, 11.0, sin(_t) * r)
	_cam.look_at(Vector3(0, 1.0, 0))
