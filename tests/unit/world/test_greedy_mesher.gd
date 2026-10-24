extends GutTest

var mesher: GreedyMesher
var stone: int
var sand: int
var water: int
var needles: int


func before_all() -> void:
	mesher = GreedyMesher.new(Registry)
	stone = Registry.block_num(&"granite")
	sand = Registry.block_num(&"sand")
	water = Registry.block_num(&"water")
	needles = Registry.block_num(&"spruce_needles")


func _empty_neighbors() -> Array:
	return [null, null, null, null, null, null]


func _section(cells: Dictionary) -> Array:
	var s := ChunkSection.new()
	for p: Vector3i in cells:
		s.set_block(WorldConst.local_index(p.x, p.y, p.z), cells[p])
	s.analyze(Registry.block_opaque, Registry.block_shape)
	return GreedyMesher.snapshot(s)


func test_empty_section() -> void:
	var r := mesher.mesh_section([0, PackedInt32Array(), false, false], _empty_neighbors())
	assert_eq(r["quads"], 0)
	assert_eq(r["opaque"], [])


func test_single_block_has_six_faces() -> void:
	var r := mesher.mesh_section(_section({ Vector3i(3, 4, 5): stone }), _empty_neighbors())
	assert_eq(r["quads"], 6)
	var arrays: Array = r["opaque"]
	assert_eq(arrays[Mesh.ARRAY_VERTEX].size(), 24)
	assert_eq(arrays[Mesh.ARRAY_INDEX].size(), 36)


func test_cube_2x2x2_merges_to_six_quads() -> void:
	var cells := {}
	for x in 2:
		for y in 2:
			for z in 2:
				cells[Vector3i(x + 5, y + 5, z + 5)] = stone
	assert_eq(mesher.mesh_section(_section(cells), _empty_neighbors())["quads"], 6)


func test_different_blocks_do_not_merge() -> void:
	var r := mesher.mesh_section(_section({ Vector3i(0, 0, 0): stone, Vector3i(1, 0, 0): sand }), _empty_neighbors())
	assert_eq(r["quads"], 10)


func test_full_uniform_section_shows_only_outer_faces() -> void:
	var r := mesher.mesh_section([stone, PackedInt32Array(), true, false], _empty_neighbors())
	assert_eq(r["quads"], 6)
	var verts: PackedVector3Array = r["opaque"][Mesh.ARRAY_VERTEX]
	for v in verts:
		assert_true(v.x == 0 or v.x == 16 or v.y == 0 or v.y == 16 or v.z == 0 or v.z == 16)


func test_enclosed_by_opaque_neighbors_has_no_faces() -> void:
	var full := [stone, PackedInt32Array(), true, false]
	var r := mesher.mesh_section(full, [full, full, full, full, full, full])
	assert_eq(r["quads"], 0)


func test_neighbor_section_culls_boundary_face() -> void:
	var nb := _empty_neighbors()
	nb[1] = _section({ Vector3i(0, 0, 0): stone })  # +X: блок вплотную к нашему (15,0,0)
	var r := mesher.mesh_section(_section({ Vector3i(15, 0, 0): stone }), nb)
	assert_eq(r["quads"], 5)


func test_water_against_stone() -> void:
	# Камень виден сквозь воду, грань воды к камню — нет, вода с водой сливается.
	var r := mesher.mesh_section(_section({
		Vector3i(0, 0, 0): stone, Vector3i(1, 0, 0): water, Vector3i(2, 0, 0): water }), _empty_neighbors())
	assert_eq(r["opaque"][Mesh.ARRAY_VERTEX].size() / 4, 6)
	# Вода 2×1×1: 4 боковые/верх/низ слились в 4 прямоугольника + торец +X; торец к камню скрыт.
	assert_eq(r["transparent"][Mesh.ARRAY_VERTEX].size() / 4, 5)


func test_cutout_shows_inner_faces() -> void:
	var r := mesher.mesh_section(_section({ Vector3i(0, 0, 0): needles, Vector3i(1, 0, 0): needles }), _empty_neighbors())
	# Внешние грани 2×1×1 сливаются (6), плюс две внутренние грани друг к другу.
	assert_eq(r["quads"], 8)


func test_winding_is_clockwise_from_outside() -> void:
	var r := mesher.mesh_section(_section({ Vector3i(3, 4, 5): stone }), _empty_neighbors())
	var a: Array = r["opaque"]
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var center := Vector3(3.5, 4.5, 5.5)
	for t in range(0, idx.size(), 3):
		var p0 := v[idx[t]]
		var p1 := v[idx[t + 1]]
		var p2 := v[idx[t + 2]]
		var normal := n[idx[t]]
		assert_gt((p0 - center).dot(normal), 0.0, "нормаль наружу")
		assert_lt((p1 - p0).cross(p2 - p0).dot(normal), 0.0, "обход по часовой (лицевая сторона Godot)")


func test_mixed_opaque_section_enclosed_has_no_faces() -> void:
	var limestone := Registry.block_num(&"limestone")
	var s := ChunkSection.filled(stone)
	for i in 2048:
		s.set_block(i, limestone)
	s.analyze(Registry.block_opaque, Registry.block_shape)
	var full := [stone, PackedInt32Array(), true, false]
	var r := mesher.mesh_section(GreedyMesher.snapshot(s), [full, full, full, full, full, full])
	assert_eq(r["quads"], 0, "граница гранит/известняк внутри камня не видна")


func test_enclosed_but_with_air_pocket_has_faces() -> void:
	var s := ChunkSection.filled(stone)
	s.set_block(WorldConst.local_index(8, 8, 8), 0)
	s.analyze(Registry.block_opaque, Registry.block_shape)
	var full := [stone, PackedInt32Array(), true, false]
	var r := mesher.mesh_section(GreedyMesher.snapshot(s), [full, full, full, full, full, full])
	assert_eq(r["quads"], 6, "полость в камне видна изнутри")


func test_cross_plant_goes_to_plants_surface() -> void:
	var grass := Registry.block_num(&"grass")
	var r := mesher.mesh_section(_section({ Vector3i(4, 4, 4): grass }), _empty_neighbors())
	assert_eq(r["quads"], 2, "крест — два квадрата")
	assert_eq(r["opaque"], [])
	assert_eq(r["plants"][Mesh.ARRAY_VERTEX].size(), 8)


func test_plant_does_not_hide_neighbor_faces() -> void:
	var grass := Registry.block_num(&"grass")
	var r := mesher.mesh_section(_section({ Vector3i(4, 4, 4): stone, Vector3i(4, 5, 4): grass }), _empty_neighbors())
	assert_eq(r["opaque"][Mesh.ARRAY_VERTEX].size() / 4, 6, "верх камня под травой виден")


func test_layer_block() -> void:
	var snow := Registry.block_num(&"snow_layer")
	var r := mesher.mesh_section(_section({ Vector3i(4, 4, 4): stone, Vector3i(4, 5, 4): snow }), _empty_neighbors())
	var verts: PackedVector3Array = r["opaque"][Mesh.ARRAY_VERTEX]
	var top := -1.0
	for v in verts:
		top = maxf(top, v.y)
	assert_almost_eq(top, 5.125, 0.001, "верх снежного слоя на 1/8 блока")
	assert_eq(r["quads"], 6 + 5, "камень 6 граней + слой: верх и 4 бока")


func test_tint_varies_across_merged_quad() -> void:
	var turf := Registry.block_num(&"turf")
	var cells := {}
	for x in 16:
		for z in 16:
			cells[Vector3i(x, 0, z)] = turf
	var tints := PackedColorArray()
	tints.resize(200)
	for i in 200:
		tints[i] = Color(0.2, 0.8, 0.2)
	for tz in 5:
		tints[2 * 25 + tz * 5 + 4] = Color(0.8, 0.6, 0.2)  # лето, трава, правый край — жёлтый
	var r := mesher.mesh_section(_section(cells), _empty_neighbors(), tints, 1)
	assert_eq(r["quads"], 6, "тонирование не мешает слиянию граней")
	var cols: PackedColorArray = r["opaque"][Mesh.ARRAY_COLOR]
	var reds := {}
	for c in cols:
		reds[snappedf(c.r, 0.01)] = true
	assert_gt(reds.size(), 1, "углы одного прямоугольника окрашены по-разному")
