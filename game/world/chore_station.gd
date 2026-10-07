class_name ChoreStation
extends Marker3D
## Where a chore step happens. Matches a "station" in Rules.CHORES.

@export var station_id := ""

var _marker: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	add_to_group("station")
	# A pulsing ring on the ground and a short, faint beam above it, so a
	# station you have work at can be spotted from across the village and
	# over fences and props.
	_marker = Node3D.new()
	_marker.visible = false
	add_child(_marker)
	_ring_mat = _glow(Color(1.0, 0.85, 0.35, 0.85))
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.1
	torus.rings = 24
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position.y = 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_ring)
	_beam_mat = _glow(Color(1.0, 0.85, 0.35, 0.16))
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.7
	cyl.height = 3.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.material_override = _beam_mat
	beam.position.y = 1.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(beam)


static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	return m


## Shows the marker while the local player has a chore step here.
func set_highlight(on: bool) -> void:
	if _marker:
		_marker.visible = on


func is_highlighted() -> bool:
	return _marker != null and _marker.visible


func _process(delta: float) -> void:
	if _marker and _marker.visible:
		_t += delta
		var pulse := sin(_t * 3.0)
		_ring_mat.albedo_color.a = 0.6 + 0.3 * pulse
		_ring.scale = Vector3.ONE * (1.0 + 0.08 * pulse)
		_beam_mat.albedo_color.a = 0.13 + 0.06 * pulse
