extends GutTest
## Сады (этап 9): сезонная листва плодовых, саженец → дерево, сбор плодов, падение срубленного
## дерева (и что дом из брёвен на фундаменте не рушится).

var world: World
var orchard: OrchardSystem
var clock: GameClock
var dropped: Array = []


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 43)
	var loam := Registry.block_num(&"loam")
	var stone := Registry.block_num(&"granite")
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
					col.set_block(x, 61, z, loam)
			world.chunks.columns[Vector2i(cx, cz)] = col
	clock = GameClock.new(24.0)
	clock.start_season = 1
	clock.season_length = 28
	clock.minute = 12 * 60.0
	orchard = OrchardSystem.new()
	orchard.animate = false
	orchard.setup(world, clock)
	dropped = []
	world.items_dropped.connect(_on_dropped)


func after_each() -> void:
	orchard.free()
	world.free()


func _on_dropped(_x: float, _y: float, _z: float, stacks: Array) -> void:
	dropped.append_array(stacks)


func _count(id: StringName) -> int:
	var n := 0
	for s: ItemStack in dropped:
		if s.id == id:
			n += s.count
	return n


func _blocks_of(b: int) -> int:
	var n := 0
	for y in range(62, 80):
		for z in range(-12, 12):
			for x in range(-12, 12):
				if world.get_block(x, y, z) == b:
					n += 1
	return n


func test_leaf_variant_rules() -> void:
	var summer := Orchard.season_mask(["summer"])
	assert_eq(Orchard.next_variant(0, 0, 0.1, summer, 0.5, 1.0), 1, "весной зацветает")
	assert_eq(Orchard.next_variant(0, 0, 0.9, summer, 0.5, 1.0), 0, "но не каждая клетка")
	assert_eq(Orchard.next_variant(2, 0, 0.9, summer, 0.5, 1.0), 0, "плоды весной опадают")
	assert_eq(Orchard.next_variant(2, 0, 0.1, summer, 0.5, 1.0), 1, "и клетка снова цветёт")
	assert_eq(Orchard.next_variant(1, 1, 0.1, summer, 0.5, 1.0), 2, "летом цвет → плоды")
	assert_eq(Orchard.next_variant(2, 2, 0.1, summer, 0.5, 1.0), 0, "осенью летние плоды опали")
	var autumn := Orchard.season_mask(["autumn"])
	assert_eq(Orchard.next_variant(1, 1, 0.1, autumn, 0.5, 1.0), 1, "цвет ждёт осенних плодов")
	assert_eq(Orchard.next_variant(1, 3, 0.1, autumn, 0.5, 1.0), 0, "зимой ничего")
	assert_eq(Orchard.next_variant(0, 1, 0.1, summer, 0.99, 1.0), 0, "дозревание — не сразу")
	assert_eq(Orchard.next_variant(0, 1, 0.1, summer, 0.99, 20.0), 2, "но за много дней дозреет")
	for v in 3:
		for s in 4:
			var once := Orchard.next_variant(v, s, 0.2, summer, 1.0, 0.0)
			assert_eq(Orchard.next_variant(once, s, 0.2, summer, 1.0, 0.0), once, "правило идемпотентно")


func test_sapling_grows_into_tree() -> void:
	var sap := Registry.block_num(&"sapling_apple")
	assert_gt(sap, 0, "саженец выведен из trees.json")
	var p := Vector3i(3, 62, 3)
	world.set_block(p.x, p.y, p.z, sap)
	assert_eq(world.get_entity(p).get("type", ""), "sapling")
	assert_true(orchard.saplings.has(p))
	clock.advance_hours(3 * 24.0)
	orchard.tick(clock.total_minutes())
	assert_eq(world.get_block(p.x, p.y, p.z), sap, "за 3 дня из 7 ещё не дерево")
	clock.advance_hours(5 * 24.0)
	orchard.tick(clock.total_minutes())
	var lg := Registry.block_num(&"apple_log")
	assert_eq(world.get_block(p.x, p.y, p.z), lg, "дерево выросло на месте саженца")
	assert_gt(_blocks_of(Registry.block_num(&"apple_leaves")), 10, "и с кроной")
	assert_false(orchard.saplings.has(p))


func test_sapling_sleeps_in_winter_and_needs_soil() -> void:
	assert_eq(Orchard.sapling_growth(7.0, 24.0, 3, true), 0.0)
	assert_eq(Orchard.sapling_growth(7.0, 24.0, 1, false), 0.0)
	assert_almost_eq(Orchard.sapling_growth(7.0, 24.0, 1, true), 1.0 / 7.0, 1e-6)


func test_fruit_season_and_harvest() -> void:
	var p := Vector3i(0, 62, 0)
	orchard.grow_tree(p, world.generator.trees.index[&"apple"])
	var leaves := Registry.block_num(&"apple_leaves")
	var blossom := Registry.block_num(&"apple_leaves_blossom")
	var fruit := Registry.block_num(&"apple_leaves_fruit")
	var total := _blocks_of(leaves)
	# Весна.
	clock.start_season = 0
	orchard.rescan_column(Vector2i(0, 0), clock.total_minutes())
	orchard.rescan_column(Vector2i(-1, 0), clock.total_minutes())
	orchard.rescan_column(Vector2i(0, -1), clock.total_minutes())
	orchard.rescan_column(Vector2i(-1, -1), clock.total_minutes())
	var b := _blocks_of(blossom)
	assert_gt(b, 0, "весной яблоня цветёт")
	assert_lt(b, total, "не вся")
	# Лето.
	clock.start_season = 1
	for c: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		orchard.rescan_column(c, clock.total_minutes())
	assert_eq(_blocks_of(blossom), 0, "цвет отцвёл")
	assert_gte(_blocks_of(fruit), b, "на месте цветов — плоды")
	# Сбор.
	var at := Vector3i.ZERO
	for y in range(62, 80):
		for z in range(-6, 6):
			for x in range(-6, 6):
				if world.get_block(x, y, z) == fruit:
					at = Vector3i(x, y, z)
	assert_true(orchard.harvest(at))
	assert_eq(world.get_block(at.x, at.y, at.z), leaves, "после сбора — обычная листва")
	assert_gt(_count(&"apple"), 0, "яблоки выпали")
	assert_false(orchard.harvest(at), "второй раз нечего")
	# Зима: всё опало.
	clock.start_season = 3
	for c: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		orchard.rescan_column(c, clock.total_minutes())
	assert_eq(_blocks_of(fruit) + _blocks_of(blossom), 0)


func test_felled_tree_falls_whole() -> void:
	var p := Vector3i(2, 62, 2)
	var t: int = world.generator.trees.index[&"birch"]
	orchard.grow_tree(p, t)
	var lg := world.generator.trees.log_block[t]
	var lv := world.generator.trees.leaves_block[t]
	var logs := _blocks_of(lg)
	assert_gt(logs, 3)
	world.set_block(p.x, p.y, p.z, 0)
	var n := orchard.fell(p, lg, Vector3(p.x - 3.0, p.y, p.z))
	assert_gt(n, logs - 1, "упали все брёвна и листва")
	assert_eq(_blocks_of(lg), 0, "брёвен не осталось")
	assert_eq(_blocks_of(lv), 0, "листвы тоже")
	assert_eq(_count(StringName(Registry.block_by_num(lg).id)), logs - 1, "брёвна выпали предметами")


func test_log_house_on_foundation_stands() -> void:
	var lg := Registry.block_num(&"oak_log")
	var stone := Registry.block_num(&"granite")
	# Стена: камень, на нём 3 ряда брёвен; ломаем одно бревно в нижнем ряду.
	for x in range(0, 5):
		world.set_block(x, 62, 0, stone)
		for y in range(63, 66):
			world.set_block(x, y, 0, lg)
	world.set_block(2, 63, 0, 0)
	assert_eq(orchard.fell(Vector3i(2, 63, 0), lg, Vector3(2, 63, -3)), 0, "стена на фундаменте стоит")
	assert_eq(_blocks_of(lg), 14)
