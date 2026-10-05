class_name Remains
extends Node3D
## What's left where a villager was taken: their lantern, tipped over and cold.

const LANTERN_SCENE := "res://assets/kenney/graveyard-kit/lantern-glass.glb"

var _wisp: MeshInstance3D
var _t := 0.0


func setup(victim_name: String) -> void:
	var lantern: Node3D = (load(LANTERN_SCENE) as PackedScene).instantiate()
	lantern.scale = Vector3.ONE * 1.3
	lantern.rotation_degrees = Vector3(0, 30, 80)
	lantern.position = Vector3(0.2, 0.15, 0)
	add_child(lantern)
	_wisp = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	_wisp.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	_wisp.material_override = mat
	_wisp.position.y = 0.6
	add_child(_wisp)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.font_size = 40
	label.outline_size = 10
	label.modulate = Color(0.75, 0.9, 1.0)
	label.text = "%s's lantern" % victim_name
	label.position.y = 1.2
	add_child(label)


func _process(delta: float) -> void:
	_t += delta
	if _wisp:
		_wisp.position.y = 0.6 + sin(_t * 2.0) * 0.12
