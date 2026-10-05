class_name RigCharacter
extends Node3D
## Plays the shared Kenney 7-part rig clips on any modern Kenney character
## (Mini Characters, Graveyard Kit, Platformer Kit, Mini Arena...).
##
## Every kit uses the same clip names, so game code only says what the
## character is doing: play("walk"), play_once("interact-right").

const LOOPING := ["idle", "walk", "sprint", "sit", "drive", "crouch", "fall",
	"holding-right", "holding-left", "holding-both", "wheelchair-sit"]

var model: Node3D
var _anim: AnimationPlayer
var _current := ""
var _one_shot := false


static func create(scene: PackedScene, scale_factor := 1.0) -> RigCharacter:
	var rc := RigCharacter.new()
	rc.set_model(scene, scale_factor)
	return rc


func set_model(scene: PackedScene, scale_factor := 1.0) -> void:
	if model:
		model.queue_free()
	model = scene.instantiate()
	model.scale = Vector3.ONE * scale_factor
	add_child(model)
	_anim = _find_player(model)
	_current = ""
	if _anim:
		for clip in LOOPING:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(_on_finished)
	play("idle")


func has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)


## Switches to a looping or held clip unless a one-shot is still playing.
func play(clip: String, blend := 0.15, speed := 1.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if _one_shot and _anim.is_playing():
		return
	if clip == _current:
		_anim.speed_scale = speed
		return
	_current = clip
	_anim.play(clip, blend, speed)


## Plays a clip once (interact, emote, pick-up); looping play() resumes after.
func play_once(clip: String, blend := 0.1, speed := 1.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_one_shot = true
	_current = clip
	_anim.play(clip, blend, speed)


func current_clip() -> String:
	return _current


func _on_finished(_name: StringName) -> void:
	_one_shot = false


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null
