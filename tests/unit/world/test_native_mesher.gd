extends GutTest
## Нативный мешер (C++) обязан выдавать то же, что GDScript-версия.

var gd: GreedyMesher
var native: Object
var gen: TerrainGenerator


func before_all() -> void:
	gd = GreedyMesher.new(Registry)
	if ClassDB.class_exists(&"NativeMesher"):
		native = GreedyMesher.create_best(Registry)
	gen = TerrainGenerator.new(4242, Registry)


func test_native_library_loaded() -> void:
	assert_true(ClassDB.class_exists(&"NativeMesher"), "native/bin: библиотека расширения загружена")
	assert_true(GreedyMesher.is_native(native))


func _compare_meshes(center: Array, nbs: Array, tints: PackedColorArray, origin: Vector3i) -> void:
	var a := gd.mesh_section(center, nbs, tints, 1, origin)
	var b: Dictionary = native.mesh_section(center, nbs, tints, 1, origin)
	assert_eq(b["quads"], a["quads"], "число граней")
	for surf in ["opaque", "transparent", "plants"]:
		var sa: Array = a[surf]
		var sb: Array = b[surf]
		assert_eq(sa.is_empty(), sb.is_empty(), surf)
		if sa.is_empty() or sb.is_empty():
			continue
		assert_eq(sb[Mesh.ARRAY_INDEX], sa[Mesh.ARRAY_INDEX], "%s: индексы" % surf)
		assert_eq(sb[Mesh.ARRAY_VERTEX], sa[Mesh.ARRAY_VERTEX], "%s: вершины" % surf)
		assert_eq(sb[Mesh.ARRAY_NORMAL], sa[Mesh.ARRAY_NORMAL], "%s: нормали" % surf)
		var ca: PackedColorArray = sa[Mesh.ARRAY_COLOR]
		var cb: PackedColorArray = sb[Mesh.ARRAY_COLOR]
		var max_diff := 0.0
		for i in ca.size():
			max_diff = maxf(max_diff, absf(ca[i].r - cb[i].r) + absf(ca[i].g - cb[i].g) + absf(ca[i].b - cb[i].b))
		assert_lt(max_diff, 0.0001, "%s: цвета" % surf)


func test_same_output_on_generated_world() -> void:
	if native == null:
		fail_test("нет нативной библиотеки")
		return
	var compared := 0
	for i in 6:
		var cpos := Vector2i(i * 9 - 20, i * 4 - 3)
		var cols := {}
		for d: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			cols[d] = gen.generate_column(cpos + d)
		var c: ChunkColumn = cols[Vector2i.ZERO]
		for si in range(8, WorldConst.SECTIONS_PER_COLUMN - 1, 3):
			var nbs := [
				GreedyMesher.snapshot(cols[Vector2i.LEFT].sections[si]), GreedyMesher.snapshot(cols[Vector2i.RIGHT].sections[si]),
				GreedyMesher.snapshot(c.sections[si - 1]), GreedyMesher.snapshot(c.sections[si + 1]),
				GreedyMesher.snapshot(cols[Vector2i.UP].sections[si]), GreedyMesher.snapshot(cols[Vector2i.DOWN].sections[si]),
			]
			_compare_meshes(GreedyMesher.snapshot(c.sections[si]), nbs, c.tints, Vector3i(cpos.x * 16, WorldConst.section_base_y(si), cpos.y * 16))
			compared += 1
	assert_gt(compared, 20)


func test_native_is_faster() -> void:
	if native == null:
		fail_test("нет нативной библиотеки")
		return
	var cpos := Vector2i(3, 3)
	var c := gen.generate_column(cpos)
	var si := WorldConst.section_index(gen.surface_height(56, 56) + 1)
	var center := GreedyMesher.snapshot(c.sections[si])
	var nbs := [null, null, GreedyMesher.snapshot(c.sections[si - 1]), GreedyMesher.snapshot(c.sections[si + 1]), null, null]
	var t0 := Time.get_ticks_usec()
	for i in 5:
		gd.mesh_section(center, nbs, c.tints, 1, Vector3i.ZERO)
	var t_gd := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in 5:
		native.mesh_section(center, nbs, c.tints, 1, Vector3i.ZERO)
	var t_native := Time.get_ticks_usec() - t0
	gut.p("мешинг секции: GDScript %.2f мс, C++ %.2f мс" % [t_gd / 5000.0, t_native / 5000.0])
	assert_lt(t_native * 5, t_gd, "C++ хотя бы в 5 раз быстрее")


func test_default_arguments() -> void:
	if native == null:
		fail_test("нет нативной библиотеки")
		return
	var stone := Registry.block_num(&"granite")
	var empty := [null, null, null, null, null, null]
	var a := gd.mesh_section([stone, PackedInt32Array(), true, false], empty)
	var b: Dictionary = native.mesh_section([stone, PackedInt32Array(), true, false], empty)
	assert_eq(b["quads"], a["quads"], "вызов без необязательных аргументов")
