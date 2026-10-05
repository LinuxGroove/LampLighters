class_name ChoreStation
extends Marker3D
## Where a chore step happens. Matches a "station" in Rules.CHORES.

@export var station_id := ""

var _marker: MeshInstance3D
var _mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	add_to_group("station")
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 0.95
	torus.rings = 24
	_marker.mesh = torus
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.8)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker.material_override = _mat
	_marker.position.y = 0.05
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


## Shows a pulsing ring when the local player has a chore step here.
func set_highlight(on: bool) -> void:
	if _marker:
		_marker.visible = on


func _process(delta: float) -> void:
	if _marker and _marker.visible:
		_t += delta
		_mat.albedo_color.a = 0.45 + 0.35 * sin(_t * 3.0)
