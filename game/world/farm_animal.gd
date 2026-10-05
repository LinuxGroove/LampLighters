extends Node3D
## A Cube Pets animal that idles and eats in its pen.

@export var model: PackedScene
@export var model_scale := 0.45

var _anim: AnimationPlayer
var _timer := 0.0


func _ready() -> void:
	if model == null:
		return
	var inst: Node3D = model.instantiate()
	inst.scale = Vector3.ONE * model_scale
	add_child(inst)
	_anim = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in ["idle", "eat"]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_timer = randf_range(0.0, 4.0)
		_anim.play("idle")


func _process(delta: float) -> void:
	if _anim == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = randf_range(3.0, 7.0)
		var clip := "eat" if randf() < 0.5 and _anim.has_animation("eat") else "idle"
		_anim.play(clip, 0.3)
