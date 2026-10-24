extends GutTest
## Дальний рельеф (LOD): шаг сетки по дальности, высоты совпадают с генератором.

var world: World
var far: FarTerrain


func before_all() -> void:
	world = World.new()
	world.setup(Registry, null, 1234)
	far = FarTerrain.new()
	far.setup(world, 1)
	far.configure(true, 32, 160.0)


func after_all() -> void:
	far.free()
	world.free()


func test_steps_by_distance() -> void:
	assert_eq(far.step_for(Vector2i(0, 0), 32.0, 32.0), 0, "плитка под игроком — внутри настоящих чанков")
	assert_eq(far.step_for(Vector2i(3, 0), 0.0, 0.0), 2)
	assert_eq(far.step_for(Vector2i(6, 0), 0.0, 0.0), 4)
	assert_eq(far.step_for(Vector2i(20, 0), 0.0, 0.0), 0, "дальше дальности LOD — нет")
	far.configure(true, 48, 160.0)
	assert_eq(far.step_for(Vector2i(10, 0), 0.0, 0.0), 8)
	far.configure(true, 32, 160.0)


func test_surface_matches_generator() -> void:
	var gen := world.generator
	var n := 5
	var step := 4
	var hs := PackedFloat32Array()
	var wl := PackedInt32Array()
	var bio := PackedInt32Array()
	for j in n:
		for i in n:
			var info := gen.surface_info(i * step, j * step)
			hs.append(float(info[0]))
			wl.append(info[1])
			bio.append(info[2])
	var arrays := far.sample_surface(hs, wl, bio, n, step)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), n * n)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), (n - 1) * (n - 1) * 6)
	for p in verts.size():
		assert_almost_eq(verts[p].y, hs[p] + 1.0 - FarTerrain.SINK, 0.001, "верх блока, опущенный на SINK")
	var v0 := verts[0]
	var v1 := verts[1]
	var v2 := verts[n + 1]
	assert_lt((v1 - v0).cross(v2 - v0).y, 0.0, "обход по часовой сверху — лицевая сторона вверх")
