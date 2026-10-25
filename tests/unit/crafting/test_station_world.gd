extends GutTest
## Станции в мире: модель в меше секции с поворотом, установка с поворотом к игроку,
## выпадение содержимого при поломке, сохранение состояния через StationSystem.

var world: World
var system: StationSystem
var clock: GameClock
var dropped: Array = []


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 5)
	world.game_mode = &"survival"
	var col := ChunkColumn.new(Vector2i(0, 0))
	var stone := Registry.block_num(&"granite")
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, stone)
	world.chunks.columns[Vector2i(0, 0)] = col
	clock = GameClock.new()
	system = StationSystem.new()
	add_child_autofree(system)
	system.setup(world, CraftingData.shared(Registry), clock)
	dropped.clear()
	world.items_dropped.connect(func(_x: float, _y: float, _z: float, stacks: Array) -> void: dropped.append_array(stacks))


func after_each() -> void:
	world.free()


func test_model_mesher() -> void:
	var mm := ModelMesher.new(Registry)
	var sec := ChunkSection.new()
	var bench := Registry.block_num(&"workbench")
	sec.set_block(WorldConst.local_index(3, 4, 5), bench)
	var center := GreedyMesher.snapshot(sec)
	assert_true(mm.any_in(center))
	var arrays := mm.build(center, {})
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var boxes := 0
	for m in Registry.block(&"workbench").model:
		if m["anim"] == &"":
			boxes += 1
	assert_eq(verts.size(), boxes * 24, "6 граней по 4 вершины на коробку")
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	assert_almost_eq(lo.y, 4.0, 0.001)
	assert_lte(hi.y, 5.2)
	assert_gte(lo.x, 3.0 - 0.001)
	# Повёрнутая модель — другие вершины, те же габариты по высоте.
	var rot := mm.build(center, { WorldConst.local_index(3, 4, 5): 1 })
	assert_ne(rot[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_VERTEX])
	assert_false(mm.any_in(GreedyMesher.snapshot(ChunkSection.filled(Registry.block_num(&"granite")))))


func test_rotate_point() -> void:
	assert_eq(ModelMesher.rotate_point(Vector3(0.5, 0.3, 0.0), 2), Vector3(0.5, 0.3, 1.0))
	assert_eq(ModelMesher.rotate_normal(Vector3.FORWARD, 2), Vector3.BACK)


func test_place_station_with_facing_and_targetable() -> void:
	var furnace := Registry.block_num(&"stone_furnace")
	assert_true(world.execute(GameAction.place_block(Vector3i(4, 61, 4), furnace, 3)))
	var e := world.get_entity(Vector3i(4, 61, 4))
	assert_eq(String(e["type"]), "station")
	assert_eq(int(e["facing"]), 3)
	assert_true(world.is_targetable(4, 61, 4), "станцию можно навести")
	await wait_frames(1)
	var st := system.get_station(Vector3i(4, 61, 4))
	assert_not_null(st, "StationSystem подхватил новую станцию")
	assert_eq(st.facing, 3)


func test_break_drops_contents_and_job() -> void:
	var p := Vector3i(6, 61, 6)
	world.execute(GameAction.place_block(p, Registry.block_num(&"crusher")))
	var st := system.station_at(p)
	st.inputs.set_stack(0, ItemStack.make(&"malachite_ore", 3))
	st.advance(1.0)   # один кусок ушёл в работу
	assert_false(st.job.is_empty())
	world.execute(GameAction.break_block(p))
	var ore := 0
	var crusher := 0
	for s: ItemStack in dropped:
		if s.id == &"malachite_ore":
			ore += s.count
		if s.id == &"crusher":
			crusher += s.count
	assert_eq(ore, 3, "и то, что в работе, тоже выпало")
	assert_eq(crusher, 1, "сама станция")
	assert_null(system.get_station(p))


func test_state_survives_unload() -> void:
	var p := Vector3i(8, 61, 8)
	world.execute(GameAction.place_block(p, Registry.block_num(&"tanning_barrel")))
	var st := system.station_at(p)
	st.inputs.set_stack(0, ItemStack.make(&"scraped_hide", 1))
	st.inputs.set_stack(1, ItemStack.make(&"oak_bark", 2))
	system._process(1.0)
	world.chunks.column_unloading.emit(Vector2i(0, 0))
	assert_null(system.get_station(p), "колонна выгружена — объекта нет")
	clock.advance_hours(50.0)
	world.chunks.column_loaded.emit(Vector2i(0, 0))
	var back := system.get_station(p)
	assert_not_null(back)
	assert_eq(back.outputs.count_of(&"tanned_hide"), 1, "за двое суток дубление закончилось само")


func test_heat_sources_and_heat_near() -> void:
	var p := Vector3i(2, 61, 2)
	world.execute(GameAction.place_block(p, Registry.block_num(&"campfire")))
	var st := system.station_at(p)
	assert_true(system.heat_sources().is_empty(), "не горит — не греет")
	st.fuel.set_stack(0, ItemStack.make(&"oak_log", 2))
	st.advance(5.0)
	assert_eq(system.heat_sources().size(), 1)
	assert_true(system.heat_near(Vector3i(3, 61, 3), 3, 300.0) == false, "костёр — не горн")
