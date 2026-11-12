extends GutTest
## Ведро, бурдюк, кипячение, плавучесть предметов, лодка (этап 8).

var world: World
var water: int
var wf: int


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 31)
	var stone := Registry.block_num(&"granite")
	water = Registry.block_num(&"water")
	wf = Registry.fluid_ids.find(&"water") + 1
	var col := ChunkColumn.new(Vector2i(0, 0))
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, stone)
			if x < 8:
				col.set_block(x, 61, z, water)
				col.set_block(x, 62, z, water)
			else:
				col.set_block(x, 61, z, stone)
				col.set_block(x, 62, z, stone)
	world.chunks.columns[Vector2i(0, 0)] = col


func after_each() -> void:
	world.free()


func _lv(n: int) -> int:
	return Registry.fluid_level_blocks[wf - 1][n]


func test_take_from_source_and_finite() -> void:
	var a := GameAction.take_fluid(Vector3i(2, 62, 2))
	assert_true(world.execute(a))
	assert_eq(a.taken, 8, "из источника — полное ведро")
	assert_eq(world.get_block(2, 62, 2), water, "источник не убывает")
	world.set_block(10, 63, 2, _lv(3))
	var b := GameAction.take_fluid(Vector3i(10, 63, 2))
	assert_true(world.execute(b))
	assert_eq(b.taken, 3)
	assert_eq(world.get_block(10, 63, 2), 0, "конечная вода ушла в ведро")
	assert_false(world.execute(GameAction.take_fluid(Vector3i(10, 62, 2))), "камень не набрать")


func test_pour_finite_water() -> void:
	var a := GameAction.pour_fluid(Vector3i(10, 63, 4), wf, 5)
	assert_true(world.execute(a))
	assert_eq(world.get_block(10, 63, 4), _lv(5))
	var b := GameAction.pour_fluid(Vector3i(10, 63, 4), wf, 6)
	assert_true(world.execute(b))
	assert_eq(b.taken, 3, "долили до полного блока")
	assert_eq(world.get_block(10, 63, 4), _lv(8))
	assert_false(world.execute(GameAction.pour_fluid(Vector3i(2, 62, 2), wf, 4)), "в источник не льётся")


func test_vessel_items_from_data() -> void:
	var bucket := Registry.item(&"wooden_bucket")
	var full := Registry.item(&"wooden_bucket_water")
	assert_eq(int(bucket.fluid_container["capacity"]), 8)
	assert_eq(String(bucket.fluid_container["filled"]), "wooden_bucket_water")
	assert_eq(String(full.fluid_container["fluid"]), "water")
	assert_false(bool(Registry.item(&"waterskin_water").fluid_container["pour"]), "бурдюк не выливают на землю")


func test_boil_purifies_water() -> void:
	var data := CraftingData.shared(Registry)
	var r := data.recipe(&"boil_water")
	assert_false(r.is_empty())
	var s := ItemStack.make(&"waterskin_water", 1, { "amount": 3, "water_kind": "dirty" })
	var consumed: Array[ItemStack] = [s]
	var out := Crafting.outputs(data, r, consumed, 0.5)
	assert_eq(out.size(), 1)
	assert_eq(out[0].id, &"waterskin_water", "сосуд тот же")
	assert_eq(String(out[0].data["water_kind"]), "purified")
	assert_eq(int(out[0].data["amount"]), 3, "воды столько же")


func test_floating_items() -> void:
	assert_true(Registry.item(&"oak_planks").floats, "доски плавают")
	assert_false(Registry.item(&"granite").floats, "камень тонет")
	assert_true(Registry.item(&"stick").floats)
	assert_false(Registry.item(&"copper_ingot").floats)


func test_boat_floats_and_rows() -> void:
	var b := Boat.new()
	b.setup(world, &"oak_boat", 4.0, 64.0, 8.0, 0.0)
	for i in 120:
		b.step(1.0 / 60.0, 0.0, 0.0)
	assert_true(b.in_water)
	assert_almost_eq(b.body.y, 63.0 - Boat.DRAFT, 0.15, "держится у поверхности")
	var z0 := b.body.z
	for i in 60:
		b.step(1.0 / 60.0, 1.0, 0.0)
	assert_lt(b.body.z, z0 - 1.0, "гребёт вперёд (−Z при yaw 0)")
	var hit := b.ray_hit(4.0, 66.0, b.body.z, Vector3.DOWN, 5.0)
	assert_gt(hit, 0.0, "луч сверху попадает в лодку")
	b.free()


func test_boat_on_land_barely_moves() -> void:
	var b := Boat.new()
	b.setup(world, &"log_raft", 12.0, 64.0, 8.0, 0.0)
	for i in 120:
		b.step(1.0 / 60.0, 1.0, 0.0)
	assert_false(b.in_water)
	assert_almost_eq(b.body.y, 63.0, 0.01, "лежит на земле")
	assert_gt(b.body.z, 8.0 - 0.3, "по суше не едет")
	b.free()
