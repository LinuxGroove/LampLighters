class_name VillageLantern
extends Node3D
## A village lamp post. Lit lanterns make a safe zone the Hollow can't act in.

@export var lantern_id := 0
@export var radius := 6.0
@export var light_height := 2.3
@export var light_color := Color(1.0, 0.72, 0.38)

var lit := true
var _light: OmniLight3D
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _flicker_left := 0.0
var _base_energy := 1.8


func _ready() -> void:
	add_to_group("lantern")
	_light = OmniLight3D.new()
	_light.position.y = light_height
	_light.omni_range = radius + 1.0
	_light.omni_attenuation = 1.2
	_light.light_color = light_color
	_light.light_energy = _base_energy
	_light.shadow_enabled = false
	add_child(_light)
	_glow = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	_glow.mesh = sphere
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(1.0, 0.85, 0.5)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = light_color
	_glow.material_override = _glow_mat
	_glow.position.y = light_height
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	# A soft halo that can be seen from across the village when lit, and a
	# small cold-blue one when out, so lit and dark lanterns read at a glance.
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.25, Color(1, 1, 1, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.billboard_keep_scale = true
	_halo_mat.albedo_texture = tex
	_halo = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_halo.mesh = quad
	_halo.material_override = _halo_mat
	_halo.position.y = light_height
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	_apply()


func set_lit(value: bool) -> void:
	if lit == value:
		return
	lit = value
	_apply()


## Ghosts can make a lantern flicker as a silent hint.
func flicker(duration := 3.0) -> void:
	_flicker_left = duration


func _process(delta: float) -> void:
	if _flicker_left > 0.0:
		_flicker_left -= delta
		var on := fmod(_flicker_left * 9.0, 1.0) > 0.45
		_light.visible = on if lit else fmod(_flicker_left * 5.0, 1.0) > 0.7
		_light.light_color = Color(0.6, 0.85, 1.0)
		if _flicker_left <= 0.0:
			_apply()
	elif lit:
		_light.light_energy = _base_energy * (0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.011 + lantern_id))


func _apply() -> void:
	if _light == null:
		return
	_light.light_color = light_color
	_light.visible = lit
	_glow_mat.albedo_color = Color(1.0, 0.85, 0.5) if lit else Color(0.25, 0.32, 0.5)
	_glow_mat.emission_enabled = lit
	_halo.scale = Vector3.ONE * (1.9 if lit else 0.7)
	_halo_mat.albedo_color = Color(1.0, 0.7, 0.35, 0.85) if lit else Color(0.35, 0.5, 0.9, 0.55)
