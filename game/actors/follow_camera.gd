class_name FollowCamera
extends Camera3D
## The three-quarter view that follows the local player, or frames the square
## during a meeting.

const OFFSET := Vector3(0, 12.5, 8.5)
const MEETING_ZOOM := 0.75
const FOLLOW_RATE := 6.0

var target: Node3D
var focus := Vector3.ZERO
var zoom := 1.0


func _ready() -> void:
	fov = 42.0
	current = true
	far = 120.0


func follow(node: Node3D) -> void:
	target = node
	zoom = 1.0


func snap_to(pos: Vector3) -> void:
	focus = pos
	_place()


func focus_meeting(pos: Vector3) -> void:
	target = null
	focus = pos
	zoom = MEETING_ZOOM
	_place()


func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		focus = focus.lerp(target.global_position, 1.0 - exp(-FOLLOW_RATE * delta))
	_place()


func _place() -> void:
	if not is_inside_tree():
		return
	global_position = focus + OFFSET * zoom
	look_at(focus + Vector3(0, 0.8, 0))
