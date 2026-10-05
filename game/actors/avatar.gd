class_name Avatar
extends Node3D
## A villager as seen on screen: the animated Mini Character (or the ghost),
## a carried lantern, a name tag and emote bubbles. Remote players glide
## towards the latest position the host sent.

const MODEL_SCALE := 1.9
const GHOST_SCENE := "res://assets/kenney/graveyard-kit/character-ghost.glb"
const LANTERN_SCENE := "res://assets/kenney/graveyard-kit/lantern-candle.glb"
const FOLLOW_RATE := 14.0

var actor_id := 0
var shown := false
var ghost := false
var ally := false
var carry := false
var rig: RigCharacter
var tag: Label3D

var _look := 0
var _name := ""
var _lantern: Node3D
var _emote: Sprite3D
var _emote_t := 0.0
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _anim := -1
var _remote := true


func setup(p_name: String, p_look: int, local := false) -> void:
	_name = p_name
	_look = p_look
	_remote = not local
	rig = RigCharacter.create(GameConfig.look_scene(_look), MODEL_SCALE)
	add_child(rig)
	rig.set_looping("interact-right")
	_attach_lantern()
	tag = Label3D.new()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.pixel_size = 0.006
	tag.font_size = 52
	tag.outline_size = 14
	tag.position.y = 1.95
	tag.text = _name
	tag.modulate = GameConfig.look_color(_look).lightened(0.25)
	tag.visible = _remote
	add_child(tag)
	_emote = Sprite3D.new()
	_emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote.no_depth_test = true
	_emote.pixel_size = 0.018
	_emote.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_emote.position.y = 2.45
	_emote.visible = false
	add_child(_emote)
	if _remote:
		visible = false


func _attach_lantern() -> void:
	var sk := rig.skeleton()
	if sk == null:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = "arm-right"
	sk.add_child(attach)
	_lantern = (load(LANTERN_SCENE) as PackedScene).instantiate()
	# The rig is scaled by MODEL_SCALE, so this is in model units.
	_lantern.scale = Vector3.ONE * 0.62
	_lantern.position = Vector3(-0.02, -0.36, 0.05)
	attach.add_child(_lantern)
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	glow.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	glow.material_override = mat
	glow.position = Vector3(0, 0.12, 0)
	_lantern.add_child(glow)


func set_flags(flags: int) -> void:
	var g := flags & 1 != 0
	if g != ghost:
		set_ghost(g)
	var al := flags & 2 != 0
	if al != ally:
		ally = al
		tag.text = _name + ("  (Hollow)" if ally else "")
		tag.modulate = Color("ff5a4f") if ally else GameConfig.look_color(_look).lightened(0.25)
	carry = flags & 4 != 0


func set_ghost(on: bool) -> void:
	ghost = on
	rig.set_model(load(GHOST_SCENE) if on else GameConfig.look_scene(_look), MODEL_SCALE)
	rig.set_looping("interact-right")
	_anim = -1
	if on:
		_lantern = null
		if tag:
			tag.modulate = Color(0.7, 0.85, 1.0, 0.8)
	else:
		_attach_lantern()


## Marks a player the Seer has looked at.
func set_marked(hollow: bool) -> void:
	tag.text = _name + ("  (Hollow!)" if hollow else "  (not Hollow)")
	if hollow:
		tag.modulate = Color("ff5a4f")


## Remote players: the host's latest position, facing and animation.
func set_target(pos: Vector3, yaw: float, anim: int) -> void:
	if not shown:
		shown = true
		visible = true
		position = pos
		rotation.y = yaw
	_target = pos
	_target_yaw = yaw
	set_anim(anim)


func hide_soon() -> void:
	if shown:
		shown = false
		visible = false


func set_anim(anim: int) -> void:
	if anim == _anim:
		return
	_anim = anim
	match anim:
		Rules.Anim.WALK:
			rig.play("walk")
		Rules.Anim.INTERACT:
			rig.play("interact-right")
		Rules.Anim.CARRY_IDLE:
			rig.play("holding-both")
		Rules.Anim.CARRY_WALK:
			rig.play("walk")
		Rules.Anim.EMOTE_YES:
			rig.play_once("emote-yes")
		Rules.Anim.EMOTE_NO:
			rig.play_once("emote-no")
		Rules.Anim.SIT:
			rig.play("sit")
		_:
			rig.play("idle")


func show_emote(tex: Texture2D) -> void:
	_emote.texture = tex
	_emote.visible = true
	_emote.scale = Vector3.ONE * 0.4
	_emote_t = 2.5
	var tw := create_tween()
	tw.tween_property(_emote, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _emote_t > 0.0:
		_emote_t -= delta
		if _emote_t <= 0.0:
			_emote.visible = false
	if _remote and shown:
		var k := 1.0 - exp(-FOLLOW_RATE * delta)
		position = position.lerp(_target, k)
		rotation.y = lerp_angle(rotation.y, _target_yaw, k)
