extends GutTest
## Животноводство (этап 9): данные и модели, кормление и любовь, детёныши, продукция (яйца,
## молоко, шерсть, навоз), вода, кормушка и гнездо, забой, движение по миру и загон из изгороди,
## сохранение.

var world: World
var clock: GameClock
var sys: AnimalSystem
var dropped: Array = []
var rng := RandomNumberGenerator.new()


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 47)
	var loam := Registry.block_num(&"loam")
	var stone := Registry.block_num(&"granite")
	for cz in range(-2, 2):
		for cx in range(-2, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
					col.set_block(x, 61, z, loam)
			world.chunks.columns[Vector2i(cx, cz)] = col
	clock = GameClock.new(24.0)
	clock.minute = 10 * 60.0
	sys = AnimalSystem.new()
	sys.setup(world, clock)
	dropped = []
	world.items_dropped.connect(_on_dropped)
	rng.seed = 5


func after_each() -> void:
	sys.free()
	world.free()


func _on_dropped(_x: float, _y: float, _z: float, stacks: Array) -> void:
	dropped.append_array(stacks)


func _count(id: StringName) -> int:
	var n := 0
	for s: ItemStack in dropped:
		if s.id == id:
			n += s.count
	return n


func _def(id: StringName) -> Dictionary:
	return Registry.get_entry("animals", id)


func test_data_and_models() -> void:
	for id: StringName in [&"cow", &"sheep", &"pig", &"goat", &"chicken"]:
		var d := _def(id)
		assert_false(d.is_empty(), "вид %s в данных" % id)
		var parts := AnimalView.build_parts(d)
		assert_gt(parts.size(), 2, "модель %s собрана из групп (тело, ноги, голова)" % id)
		var has_legs := false
		for p: Dictionary in parts:
			if p["anim"] in ["leg_a", "leg_b"]:
				has_legs = true
		assert_true(has_legs, "у %s ноги анимируются" % id)
	assert_not_null(Registry.item(&"feather"))
	assert_true(Registry.block_num(&"fence_oak") > 0 and Registry.block_num(&"feeder") > 0)


func test_food_and_love() -> void:
	var d := _def(&"cow")
	var a := sys.spawn(&"cow", 0.5, 62.0, 0.5)
	var now := clock.total_minutes()
	assert_true(AnimalLife.accepts(d, Registry.item(&"wheat")), "корова ест зерно (#grain)")
	assert_false(AnimalLife.accepts(d, Registry.item(&"egg")))
	assert_true(AnimalLife.feed(a, d, now))
	assert_true(AnimalLife.is_fed(a, now))
	assert_true(AnimalLife.in_love(a, now), "сытый взрослый влюбляется")
	assert_false(AnimalLife.feed(a, d, now), "второй раз сразу — не ест")
	var b := sys.spawn(&"cow", 1.5, 62.0, 0.5)
	AnimalLife.feed(b, d, now)
	assert_true(AnimalLife.can_breed(a, b, d, now))
	var calf := AnimalLife.breed(a, b, d, now)
	assert_false(AnimalLife.is_adult(calf, d, now), "детёныш")
	assert_true(AnimalLife.is_adult(calf, d, now + 4.0 * 1440.0 + 1.0), "через adult_days — взрослый")
	assert_false(AnimalLife.in_love(a, now), "после родов любовь прошла")
	assert_false(AnimalLife.feed(a, d, now + 60.0) and AnimalLife.in_love(a, now + 60.0), "и отдых breed_days")


func test_products() -> void:
	var cd := _def(&"chicken")
	var c := sys.spawn(&"chicken", 0.5, 62.0, 0.5)
	var now := clock.total_minutes()
	AnimalLife.feed(c, cd, now)
	c.water_seen = now
	var t := now + 24.0 * 60.0 + 1.0
	c.water_seen = t
	c.fed_until = t + 100.0
	var got := AnimalLife.due(c, cd, t, rng)
	var eggs := 0
	for g: Array in got:
		if g[0] == &"egg":
			eggs += int(g[1])
	assert_eq(eggs, 1, "сытая напоенная курица несётся раз в сутки")
	assert_eq(AnimalLife.due(c, cd, t + 10.0, rng).filter(func(g: Array) -> bool: return g[0] == &"egg").size(), 0, "не чаще")
	# Корова: молоко — сытая и с водой, раз в сутки.
	var md := _def(&"cow")
	var cow := sys.spawn(&"cow", 2.5, 62.0, 0.5)
	var mi := AnimalLife.product_index(md, "milk")
	var t2 := now + 25.0 * 60.0
	assert_false(AnimalLife.can_take(cow, md, mi, t2), "голодная — без молока")
	cow.fed_until = t2 + 600.0
	cow.water_seen = t2
	assert_true(AnimalLife.can_take(cow, md, mi, t2))
	var milk := AnimalLife.take(cow, md, mi, t2, rng)
	assert_eq(milk[0], &"milk")
	assert_gte(int(milk[1]), 2)
	assert_false(AnimalLife.can_take(cow, md, mi, t2 + 60.0), "следующее — через сутки")
	# Овца: шерсть есть сразу, после стрижки отрастает.
	var sd := _def(&"sheep")
	var sh := sys.spawn(&"sheep", 4.5, 62.0, 0.5)
	var si := AnimalLife.product_index(sd, "shear")
	assert_true(AnimalLife.can_take(sh, sd, si, now))
	AnimalLife.take(sh, sd, si, now, rng)
	assert_false(AnimalLife.can_take(sh, sd, si, now + 60.0))
	assert_true(AnimalLife.can_take(sh, sd, si, now + 73.0 * 60.0), "отросла за every_hours")


func test_drops_adult_and_baby() -> void:
	var d := _def(&"pig")
	var adult := AnimalLife.drops(d, true, rng)
	var baby := AnimalLife.drops(d, false, rng)
	assert_eq(adult[0][0], &"pork")
	assert_gte(int(adult[0][1]), 2)
	assert_gte(int(baby[0][1]), 1, "детёныш даёт меньше, но не ноль")
	var a := sys.spawn(&"pig", 0.5, 62.0, 0.5)
	sys.hit(a, 100.0, Vector3(3, 62, 0))
	assert_eq(sys.animals.size(), 0, "забитое животное убрано")
	assert_gt(_count(&"pork"), 0, "мясо выпало")


func test_walks_on_ground_and_pen_holds() -> void:
	var fence := Registry.block_num(&"fence_oak")
	# Загон 5×5 внутри изгороди (по периметру 7×7).
	for i in range(-3, 4):
		for p: Vector2i in [Vector2i(i, -3), Vector2i(i, 3), Vector2i(-3, i), Vector2i(3, i)]:
			world.set_block(p.x, 62, p.y, fence)
	var a := sys.spawn(&"sheep", 0.5, 62.0, 0.5)
	var now := clock.total_minutes()
	for i in 60 * 40:
		if i % 120 == 0:
			a.state = Animal.State.WANDER
			a.tx = a.x + (8.0 if (i / 120) % 2 == 0 else -8.0)
			a.tz = a.z + (6.0 if (i / 240) % 2 == 0 else -6.0)
			a.timer = 2.0
		sys.step(a, 1.0 / 60.0, now)
	assert_almost_eq(a.y, 62.0, 0.05, "стоит на земле, не провалилось")
	assert_true(absf(a.x) < 3.0 and absf(a.z) < 3.0, "изгородь держит (x %.2f, z %.2f)" % [a.x, a.z])


func test_steps_up_one_block() -> void:
	var stone := Registry.block_num(&"granite")
	for z in range(-2, 3):
		world.set_block(3, 62, z, stone)
	var a := sys.spawn(&"cow", 0.5, 62.0, 0.5)
	a.state = Animal.State.WANDER
	a.tx = 6.5
	a.tz = 0.5
	a.timer = 30.0
	for i in 60 * 8:
		sys.step(a, 1.0 / 60.0, clock.total_minutes())
		if a.state != Animal.State.WANDER:
			a.state = Animal.State.WANDER
			a.timer = 30.0
	assert_gt(a.x, 3.5, "запрыгнуло на ступеньку в блок и прошло дальше")


func test_feeder_and_nest() -> void:
	var feeder := Vector3i(2, 62, 0)
	world.execute(GameAction.place_block(feeder, Registry.block_num(&"feeder"), 0))
	assert_true(sys.feeders.has(feeder), "кормушка найдена")
	var inv := world.get_container(feeder.x, feeder.y, feeder.z)
	inv.add(ItemStack.create(Registry.item(&"wheat"), 5))
	assert_eq(int(world.get_entity(feeder).get("facing", -1)), 0, "поворот кормушки не потерялся")
	var a := sys.spawn(&"cow", 2.5, 62.0, 1.5)
	var now := clock.total_minutes()
	assert_true(sys.eat_from_feeder(a, feeder, now))
	assert_true(AnimalLife.is_fed(a, now))
	assert_eq(inv.count_of(&"wheat"), 4, "съела одно зерно")
	# Гнездо: курица несётся туда.
	var nest := Vector3i(-2, 62, 0)
	world.execute(GameAction.place_block(nest, Registry.block_num(&"nest_box"), 0))
	var c := sys.spawn(&"chicken", -1.5, 62.0, 0.5)
	c.fed_until = now + 3000.0
	c.water_seen = now + 24.0 * 60.0 + 1.0
	sys.life_tick(now + 24.0 * 60.0 + 1.0)
	var ninv := world.get_container(nest.x, nest.y, nest.z)
	var eggs := 0
	for i in ninv.size():
		var s := ninv.get_stack(i)
		if s != null and s.id == &"egg":
			eggs += s.count
	assert_eq(eggs, 1, "яйцо в гнезде, а не на земле")


func test_water_near() -> void:
	var a := sys.spawn(&"cow", 0.5, 62.0, 0.5)
	var now := clock.total_minutes()
	sys.life_tick(now)
	assert_false(AnimalLife.is_watered(a, now), "воды нет")
	world.set_block(4, 61, 0, Registry.block_num(&"water"))
	a.water_seen = -1.0
	sys.life_tick(now)
	assert_true(AnimalLife.is_watered(a, now), "вода в 4 блоках — напоена")


func test_save_roundtrip() -> void:
	var a := sys.spawn(&"goat", 3.25, 62.0, -1.5)
	a.fed_until = 1234.0
	var arr := sys.to_array()
	var sys2 := AnimalSystem.new()
	sys2.setup(world, clock)
	sys2.from_array(JSON.parse_string(JSON.stringify(arr)))
	assert_eq(sys2.animals.size(), 1)
	var b: Animal = sys2.animals[0]
	assert_eq(b.id, &"goat")
	assert_almost_eq(b.x, 3.25, 1e-6)
	assert_almost_eq(b.fed_until, 1234.0, 1e-6)
	assert_eq(b.next.size(), a.next.size())
	sys2.free()
