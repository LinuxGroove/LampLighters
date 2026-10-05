extends SceneTree
## Generates res://game/world/moonpatch_village.tscn from Kenney kit pieces.
##
##   godot --headless --path . -s tools/build_village.gd
##
## The output is an ordinary scene: tweak it in the editor afterwards, or edit
## the layout below and regenerate. Gameplay reads lanterns, chore stations,
## the bell, spawns, landmarks and obstacles from it by group and node name.

const OUT := "res://game/world/moonpatch_village.tscn"
const FT := "res://assets/kenney/fantasy-town-kit/"
const GY := "res://assets/kenney/graveyard-kit/"
const SV := "res://assets/kenney/survival-kit/"
const FD := "res://assets/kenney/food-kit/"
const PETS := "res://assets/kenney/cube-pets/"

const FT_SCALE := 2.0
const GY_SCALE := 1.6
const SV_SCALE := 3.0

var village: Village
var props: Node3D
var obstacles: Node3D
var rng := RandomNumberGenerator.new()
var _lantern_id := 0
var _cache := {}


func _init() -> void:
	rng.seed = 1406
	village = Village.new()
	village.name = "MoonpatchVillage"
	village.map_name = "Moonpatch Village"
	village.bounds = Rect2(-30, -30, 60, 60)
	props = _group("Props")
	obstacles = _group("Obstacles")
	_group("Lanterns")
	_group("Stations")
	_group("Landmarks")
	_group("Spawns")
	_group("Animals")

	_environment()
	_ground()
	_square()
	_chapel()
	_graveyard()
	_market()
	_farm()
	_hayfield()
	_woodpile_and_campfire()
	_houses()
	_border()

	_set_owner(village, village)
	var packed := PackedScene.new()
	var err := packed.pack(village)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	print("Saved %s (%d)" % [OUT, err])
	quit(0 if err == OK else 1)


# --- Areas ---------------------------------------------------------------

func _environment() -> void:
	var env_node := WorldEnvironment.new()
	env_node.name = "Night"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.62)
	env.ambient_light_energy = 0.14
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.12)
	env.fog_density = 0.012
	env_node.environment = env
	village.add_child(env_node)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.14
	moon.rotation_degrees = Vector3(-60, -30, 0)
	moon.shadow_enabled = false
	village.add_child(moon)


func _ground() -> void:
	var ground := Node3D.new()
	ground.name = "Ground"
	village.add_child(ground)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.24, 0.42, 0.24)
	grass.roughness = 1.0
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.3, 0.32, 0.26)
	dirt.roughness = 1.0
	# Small chunks keep each mesh under the Mobile renderer's per-mesh light limit.
	var chunk := 10.0
	for x in range(-3, 3):
		for z in range(-3, 3):
			var m := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(chunk, chunk)
			m.mesh = plane
			var center := Vector3((x + 0.5) * chunk, 0, (z + 0.5) * chunk)
			m.position = center
			m.material_override = dirt if (center.x > 10 and center.z < -8) else grass
			m.name = "Ground_%d_%d" % [x + 3, z + 3]
			ground.add_child(m)
	# Roads from the square to each area
	for z in range(-7, 0):
		_piece(FT + "road.glb", Vector3(0, 0.01, z * 2 - 1), 0, FT_SCALE)
	for z in range(1, 9):
		_piece(FT + "road.glb", Vector3(0, 0.01, z * 2 + 1), 0, FT_SCALE)
	for x in range(1, 6):
		_piece(FT + "road.glb", Vector3(x * 2 + 1, 0.01, 0), 0, FT_SCALE)
	for x in range(-6, 0):
		_piece(FT + "road.glb", Vector3(x * 2 - 1, 0.01, 0), 0, FT_SCALE)
	# Diagonal paths: tiles 1.41 m apart on each axis so they touch.
	for i in range(2, 9):
		var d := i * 1.414
		_piece(FT + "road.glb", Vector3(d, 0.012, -d), 45, FT_SCALE)
		_piece(FT + "road.glb", Vector3(-d, 0.012, d), 45, FT_SCALE)
		_piece(FT + "road.glb", Vector3(d, 0.012, d), -45, FT_SCALE)
	# Grass tufts for texture
	for i in 160:
		var p := Vector3(rng.randf_range(-28, 28), 0, rng.randf_range(-28, 28))
		if absf(p.x) < 2.5 or absf(p.z) < 2.5:
			continue
		_piece(SV + ("grass.glb" if rng.randf() < 0.7 else "grass-large.glb"), p, rng.randf_range(0, 360), SV_SCALE)


func _square() -> void:
	_piece(FT + "fountain-round.glb", Vector3(0, 0, 0), 0, FT_SCALE)
	_piece(FT + "fountain-center.glb", Vector3(0, 0, 0), 0, FT_SCALE)
	_cyl(Vector3(0, 0, 0), 2.1)
	_station("fountain", Vector3(0, 0, 2.9))
	_landmark("the square", Vector3(0, 0, 0))
	_landmark("the fountain", Vector3(0, 0, 2.5))
	_bell(Vector3(4.6, 0, -3.2))
	for p in [Vector3(5.5, 0, 5.5), Vector3(-5.5, 0, 5.5), Vector3(5.5, 0, -5.5), Vector3(-5.5, 0, -5.5)]:
		_lantern(p)
	var spawns: Node = village.get_node("Spawns")
	for i in 10:
		var a := TAU * i / 10.0 + 0.3
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3(cos(a), 0, sin(a)) * 4.8
		spawns.add_child(m)
	for p in [Vector3(-3.2, 0, 4.4), Vector3(3.2, 0, 4.4)]:
		_piece(GY + "bench.glb", p, 0, GY_SCALE)


func _chapel() -> void:
	_house(Vector3(-2, 0, -26), 2, 3, "south", true)
	_piece(GY + "altar-stone.glb", Vector3(0, 0, -17), 0, GY_SCALE)
	_piece(GY + "candle-multiple.glb", Vector3(-0.5, 0.78, -17), 0, GY_SCALE)
	_piece(GY + "candle-multiple.glb", Vector3(0.5, 0.78, -17), 30, GY_SCALE)
	_box(Vector3(0, 0, -17), Vector3(1.7, 1, 1.1))
	_station("chapel", Vector3(0, 0, -15.6))
	_landmark("the chapel", Vector3(0, 0, -18))
	_lantern(Vector3(-3.4, 0, -15.5))
	_lantern(Vector3(3.4, 0, -15.5))
	for p in [Vector3(-4.5, 0, -24), Vector3(4.5, 0, -22), Vector3(-5, 0, -19)]:
		_tree(p)


func _graveyard() -> void:
	var x0 := 12.0
	var x1 := 27.0
	var z0 := -27.0
	var z1 := -9.0
	# Iron fence, with a gate gap on the west side
	# Iron fence panels sit 0.33 units off their origin, so shift them onto the line.
	var off := 0.33 * GY_SCALE
	var x := x0
	while x < x1 - 0.1:
		_piece(GY + "iron-fence.glb", Vector3(x + 0.8, 0, z0 + off), 0, GY_SCALE)
		_piece(GY + ("iron-fence-damaged.glb" if rng.randf() < 0.2 else "iron-fence.glb"), Vector3(x + 0.8, 0, z1 + off), 0, GY_SCALE)
		x += 1.6
	var z := z0
	while z < z1 - 0.1:
		if absf(z + 0.8 + 17.0) > 1.6:
			_piece(GY + "iron-fence.glb", Vector3(x0 + off, 0, z + 0.8), 90, GY_SCALE)
		_piece(GY + "iron-fence.glb", Vector3(x1 + off, 0, z + 0.8), 90, GY_SCALE)
		z += 1.6
	_box(Vector3((x0 + x1) / 2, 0, z0), Vector3(x1 - x0, 1, 0.3))
	_box(Vector3((x0 + x1) / 2, 0, z1), Vector3(x1 - x0, 1, 0.3))
	_box(Vector3(x1, 0, (z0 + z1) / 2), Vector3(0.3, 1, z1 - z0))
	_box(Vector3(x0, 0, (z0 + (-18.8)) / 2), Vector3(0.3, 1, -18.8 - z0))
	_box(Vector3(x0, 0, (-15.2 + z1) / 2), Vector3(0.3, 1, z1 - (-15.2)))
	# Gravestones in rows
	var stones := ["gravestone-round.glb", "gravestone-cross.glb", "gravestone-bevel.glb", "gravestone-broken.glb", "gravestone-wide.glb"]
	for row in 3:
		for col in 4:
			var p := Vector3(16 + col * 2.6, 0, -24.5 + row * 3.2)
			if Vector2(p.x - 19, p.z + 17).length() < 3.0:
				continue
			_piece(GY + stones[rng.randi() % stones.size()], p, rng.randf_range(-8, 8), GY_SCALE)
			_box(p, Vector3(0.8, 1, 0.4))
	_piece(GY + "crypt.glb", Vector3(23.5, 0, -14), -90, GY_SCALE * 1.4)
	_box(Vector3(23.5, 0, -14), Vector3(2.4, 1, 1.6))
	_piece(GY + "grave.glb", Vector3(19, 0, -17.5), 90, GY_SCALE)
	_piece(GY + "shovel-dirt.glb", Vector3(20.3, 0, -16.8), 20, GY_SCALE)
	_station("grave", Vector3(19, 0, -16))
	_landmark("the graveyard", Vector3(19, 0, -19))
	_landmark("the graveyard gate", Vector3(11, 0, -17))
	for p in [Vector3(14, 0, -11), Vector3(25.5, 0, -25.5), Vector3(14, 0, -25.5), Vector3(25.5, 0, -10.5)]:
		_piece(GY + ("pine-crooked.glb" if rng.randf() < 0.5 else "pine.glb"), p, rng.randf_range(0, 360), GY_SCALE * 1.3)
		_cyl(p, 0.6)
	for p in [Vector3(17, 0, -13), Vector3(22, 0, -20)]:
		_piece(GY + "pumpkin-carved.glb", p, rng.randf_range(0, 360), GY_SCALE)
	_lantern(Vector3(10.6, 0, -15.0), true)


func _market() -> void:
	var stalls := ["stall-red.glb", "stall-green.glb", "stall-red.glb"]
	for i in 3:
		var p := Vector3(11.5 + i * 3.4, 0, -2.4)
		_piece(FT + stalls[i], p, 0, FT_SCALE)
		_box(p, Vector3(2.0, 1, 2.0))
	var food := ["apple.glb", "bread.glb", "cheese.glb", "carrot.glb", "cabbage.glb", "corn.glb"]
	for i in 6:
		_piece(FD + food[i], Vector3(10.8 + i * 1.6, 1.0, -1.7), rng.randf_range(0, 360), 1.6)
	_piece(SV + "barrel.glb", Vector3(19.6, 0, -1.2), 0, SV_SCALE)
	_piece(SV + "box.glb", Vector3(19.4, 0, -3.2), 15, SV_SCALE)
	_cyl(Vector3(19.6, 0, -1.2), 0.45)
	_station("market", Vector3(14.9, 0, 0.0))
	_landmark("the market", Vector3(15, 0, -1))
	_lantern(Vector3(10.0, 0, 2.6))
	_lantern(Vector3(20.5, 0, 2.6))


func _farm() -> void:
	var x0 := 12.0
	var x1 := 20.0
	var z0 := 12.0
	var z1 := 19.0
	# Fence panels sit on the +X edge of their cell (0.46 units out).
	var off := 0.46 * FT_SCALE
	var x := x0
	while x < x1 - 0.1:
		_piece(FT + "fence.glb", Vector3(x + 1, 0, z0 + off), 90, FT_SCALE)
		var broken := absf(x + 1 - 16) < 0.5
		_piece(FT + ("fence-broken.glb" if broken else "fence.glb"), Vector3(x + 1, 0, z1 + off), 90, FT_SCALE)
		x += 2.0
	var z := z0
	while z < z1 - 0.1:
		var step := minf(2.0, z1 - z)
		_piece(FT + "fence.glb", Vector3(x0 - off, 0, z + step / 2), 0, FT_SCALE)
		_piece(FT + "fence.glb", Vector3(x1 - off, 0, z + step / 2), 0, FT_SCALE)
		z += 2.0
	_box(Vector3((x0 + x1) / 2, 0, z0), Vector3(x1 - x0, 1, 0.3))
	_box(Vector3((x0 + x1) / 2, 0, z1), Vector3(x1 - x0, 1, 0.3))
	_box(Vector3(x0, 0, (z0 + z1) / 2), Vector3(0.3, 1, z1 - z0))
	_box(Vector3(x1, 0, (z0 + z1) / 2), Vector3(0.3, 1, z1 - z0))
	_animal("animal-cow.glb", Vector3(15, 0, 14.5), 30)
	_animal("animal-pig.glb", Vector3(17.5, 0, 16.5), -60)
	_animal("animal-chick.glb", Vector3(14, 0, 17), 120)
	_animal("animal-chick.glb", Vector3(18.5, 0, 13.6), 200)
	_piece(SV + "box-large.glb", Vector3(13.0, 0, 15.5), 0, SV_SCALE * 0.8)
	_piece(SV + "bucket.glb", Vector3(11.3, 0, 14.3), 0, SV_SCALE)
	_station("pen", Vector3(11.0, 0, 15.5))
	_station("fence", Vector3(16, 0, 20.4))
	_landmark("the farm", Vector3(16, 0, 15.5))
	_landmark("the broken fence", Vector3(16, 0, 20))
	_lantern(Vector3(10.2, 0, 11.4))
	_lantern(Vector3(21.6, 0, 20.6))


func _hayfield() -> void:
	var bales := [Vector3(-1.5, 0, 23), Vector3(0.5, 0, 23.2), Vector3(2.4, 0, 22.8), Vector3(-0.5, 0.56, 23.1), Vector3(1.5, 0.56, 23)]
	for i in bales.size():
		_piece(GY + ("hay-bale-bundled.glb" if i % 2 == 0 else "hay-bale.glb"), bales[i], rng.randf_range(-10, 10), GY_SCALE)
	_box(Vector3(0.5, 0, 23), Vector3(5.6, 1, 1.4))
	_piece(FT + "cart.glb", Vector3(5.5, 0, 22.5), 70, FT_SCALE)
	_box(Vector3(5.5, 0, 22.5), Vector3(2.6, 1, 1.6))
	_station("hay", Vector3(0.5, 0, 21.2))
	_landmark("the hayfield", Vector3(0.5, 0, 22))
	_lantern(Vector3(-3.2, 0, 19.6))


func _woodpile_and_campfire() -> void:
	_piece(SV + "tree-log.glb", Vector3(-19, 0, 18.5), 10, SV_SCALE)
	_piece(SV + "tree-log.glb", Vector3(-19.3, 0, 19.6), -5, SV_SCALE)
	_piece(SV + "resource-wood.glb", Vector3(-17.8, 0, 17.6), 30, SV_SCALE * 1.2)
	_piece(SV + "resource-wood.glb", Vector3(-18.6, 0, 17.4), -20, SV_SCALE * 1.2)
	_piece(SV + "tool-axe.glb", Vector3(-17.2, 0, 18.8), 80, SV_SCALE)
	_piece(SV + "workbench.glb", Vector3(-21.4, 0, 16.6), 0, SV_SCALE)
	_box(Vector3(-19.2, 0, 19), Vector3(3.2, 1, 2.2))
	_box(Vector3(-21.4, 0, 16.6), Vector3(1.0, 1, 1.0))
	_station("woodpile", Vector3(-17.0, 0, 16.4))
	_landmark("the woodpile", Vector3(-18.5, 0, 17.5))
	_piece(SV + "campfire-pit.glb", Vector3(-9, 0, 9), 0, SV_SCALE)
	var fire := OmniLight3D.new()
	fire.name = "CampfireLight"
	fire.position = Vector3(-9, 0.6, 9)
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 1.2
	fire.omni_range = 4.0
	village.add_child(fire)
	_cyl(Vector3(-9, 0, 9), 0.5)
	for a in [0.0, 120.0, 240.0]:
		var p := Vector3(-9, 0, 9) + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * 2.0
		_piece(SV + "tree-log.glb", p, -a + 90, SV_SCALE * 0.7)
	_station("campfire", Vector3(-9, 0, 7.4))
	_landmark("the campfire", Vector3(-9, 0, 9))
	_lantern(Vector3(-13.5, 0, 12.5))


func _houses() -> void:
	_house(Vector3(-16, 0, -7), 2, 3, "east")
	_house(Vector3(-25, 0, -8), 2, 2, "east")
	_house(Vector3(-17, 0, -18), 2, 2, "south")
	_house(Vector3(-9, 0, -14), 2, 2, "east")
	_house(Vector3(-24, 0, 4), 2, 2, "north")
	_house(Vector3(6, 0, -14), 2, 2, "west")
	_house(Vector3(-5, 0, 11), 2, 2, "north")
	_landmark("the houses", Vector3(-16, 0, -4))
	_landmark("the north houses", Vector3(-14, 0, -14))
	_landmark("the old house", Vector3(8, 0, -11))
	_lantern(Vector3(-10.5, 0, -2.6))
	_lantern(Vector3(-12.5, 0, -10.0))
	_lantern(Vector3(5.0, 0, -9.5))
	_lantern(Vector3(-21, 0, 2.0))


func _border() -> void:
	var trees := [FT + "tree.glb", FT + "tree-high.glb", FT + "tree-crooked.glb", FT + "tree-high-round.glb"]
	var t := -29.0
	while t <= 29.0:
		for edge in 4:
			var p: Vector3
			match edge:
				0: p = Vector3(t, 0, -29.0)
				1: p = Vector3(t, 0, 29.0)
				2: p = Vector3(-29.0, 0, t)
				3: p = Vector3(29.0, 0, t)
			p += Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			if edge == 3 and p.z < -8 and p.z > -28:
				continue
			_piece(trees[rng.randi() % trees.size()], p, rng.randf_range(0, 360), FT_SCALE * rng.randf_range(0.85, 1.15))
		t += 3.2
	for p in [Vector3(-26, 0, 22), Vector3(24, 0, 6), Vector3(-6, 0, 26), Vector3(8, 0, 25), Vector3(-26, 0, -26)]:
		_piece(FT + "rock-large.glb", p, rng.randf_range(0, 360), FT_SCALE * 0.8)
		_cyl(p, 1.2)
	for p in [Vector3(-12, 0, 24), Vector3(25, 0, 12), Vector3(-25, 0, 13)]:
		_tree(p)


# --- Builders ------------------------------------------------------------

## A Fantasy Town Kit house of w x d cells (2 m each), with a gable roof.
func _house(corner: Vector3, w: int, d: int, door: String, chapel := false) -> void:
	var cell := FT_SCALE
	var house := Node3D.new()
	house.name = "House_%d_%d" % [int(corner.x), int(corner.z)]
	props.add_child(house)
	var door_cell := Vector2i(w - 1 if door == "east" else 0, d / 2)
	match door:
		"south": door_cell = Vector2i(w / 2, d - 1)
		"north": door_cell = Vector2i(w / 2, 0)
		"west": door_cell = Vector2i(0, d / 2)
	for i in w:
		for j in d:
			var center := corner + Vector3((i + 0.5) * cell, 0, (j + 0.5) * cell)
			var sides := []
			if i == w - 1: sides.append(["east", 0.0])
			if j == 0: sides.append(["north", 90.0])
			if i == 0: sides.append(["west", 180.0])
			if j == d - 1: sides.append(["south", -90.0])
			for s in sides:
				var piece := "wall.glb"
				if s[0] == door and Vector2i(i, j) == door_cell:
					piece = "wall-door.glb"
				elif rng.randf() < 0.45:
					piece = "wall-window-shutters.glb" if not chapel else "wall-window-round.glb"
				_piece_in(house, FT + piece, center, s[1], cell)
				if chapel:
					_piece_in(house, FT + "wall.glb", center + Vector3(0, cell, 0), s[1], cell)
	var roof_y := cell * (2.0 if chapel else 1.0)
	for j in d:
		var z := corner.z + (j + 0.5) * cell
		_piece_in(house, FT + "roof.glb", Vector3(corner.x + 0.5 * cell, roof_y, z), 0, cell)
		_piece_in(house, FT + "roof.glb", Vector3(corner.x + 1.5 * cell, roof_y, z), 180, cell)
	if not chapel and rng.randf() < 0.7:
		_piece_in(house, FT + "chimney.glb", corner + Vector3(1.4 * cell, roof_y, 0.6 * cell), 0, cell)
	var size := Vector3(w * cell, 2, d * cell)
	_box(corner + size * Vector3(0.5, 0, 0.5), size)


func _bell(pos: Vector3) -> void:
	var bell := Marker3D.new()
	bell.name = "Bell"
	bell.position = pos
	bell.add_to_group("bell", true)
	village.add_child(bell)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.28, 0.16)
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.85, 0.62, 0.25)
	bronze.metallic = 0.7
	bronze.roughness = 0.35
	for x in [-0.55, 0.55]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.16, 2.6, 0.16)
		post.mesh = pm
		post.material_override = wood
		post.position = Vector3(x, 1.3, 0)
		bell.add_child(post)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 0.16, 0.2)
	beam.mesh = bm
	beam.material_override = wood
	beam.position = Vector3(0, 2.6, 0)
	bell.add_child(beam)
	var cup := MeshInstance3D.new()
	cup.name = "BellCup"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.36
	cm.height = 0.55
	cup.mesh = cm
	cup.material_override = bronze
	cup.position = Vector3(0, 2.2, 0)
	bell.add_child(cup)
	var clapper := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	clapper.mesh = sm
	clapper.material_override = bronze
	clapper.position = Vector3(0, 1.9, 0)
	bell.add_child(clapper)
	_box(pos, Vector3(1.4, 1, 0.4))
	_landmark("the bell", pos)


func _lantern(pos: Vector3, graveyard := false) -> void:
	var holder: Node = village.get_node("Lanterns")
	var lantern := Node3D.new()
	lantern.set_script(load("res://game/world/village_lantern.gd"))
	lantern.name = "Lantern%d" % _lantern_id
	lantern.position = pos
	lantern.set("lantern_id", _lantern_id)
	_lantern_id += 1
	holder.add_child(lantern)
	if graveyard:
		_piece_in(lantern, GY + "lightpost-single.glb", Vector3.ZERO, 0, GY_SCALE * 1.4)
		lantern.set("light_height", 1.9)
	else:
		_piece_in(lantern, FT + "lantern.glb", Vector3.ZERO, 0, 1.6)
		lantern.set("light_height", 2.25)
	_cyl(pos, 0.25)


func _station(id: String, pos: Vector3) -> void:
	var s := Marker3D.new()
	s.set_script(load("res://game/world/chore_station.gd"))
	s.name = "Station_" + id
	s.set("station_id", id)
	s.position = pos
	village.get_node("Stations").add_child(s)


func _landmark(label: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = label.replace(" ", "_")
	m.position = pos
	village.get_node("Landmarks").add_child(m)


func _animal(file: String, pos: Vector3, yaw: float) -> void:
	var a := Node3D.new()
	a.set_script(load("res://game/world/farm_animal.gd"))
	a.name = file.get_basename().capitalize().replace(" ", "")
	a.position = pos
	a.rotation_degrees.y = yaw
	a.set("model", load(PETS + file))
	a.set("model_scale", 0.45)
	village.get_node("Animals").add_child(a)


func _tree(pos: Vector3) -> void:
	_piece(FT + ("tree.glb" if rng.randf() < 0.5 else "tree-high.glb"), pos, rng.randf_range(0, 360), FT_SCALE)
	_cyl(pos, 0.6)


func _piece(path: String, pos: Vector3, yaw_deg: float, s: float) -> Node3D:
	return _piece_in(props, path, pos, yaw_deg, s)


func _piece_in(parent: Node, path: String, pos: Vector3, yaw_deg: float, s: float) -> Node3D:
	if not _cache.has(path):
		_cache[path] = load(path)
	var n: Node3D = _cache[path].instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	return n


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("obstacle", true)
	body.position = Vector3(center.x, size.y * 0.5, center.z)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	obstacles.add_child(body)


func _cyl(center: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("obstacle", true)
	body.position = Vector3(center.x, 1.0, center.z)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 2.0
	cs.shape = shape
	body.add_child(cs)
	obstacles.add_child(body)


func _group(group_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = group_name
	village.add_child(n)
	return n


## Instanced pieces keep their own children; only direct additions are owned,
## so the saved scene references the GLBs instead of copying them.
func _set_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		if child.scene_file_path == "":
			_set_owner(child, owner_node)
