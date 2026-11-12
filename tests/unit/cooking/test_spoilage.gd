extends GutTest
## Порча еды: ступени свежести, скорость по температуре, ледник, досчёт хранилища, стопки.

var rng := RandomNumberGenerator.new()


func before_each() -> void:
	rng.seed = 5


func test_rate_by_temperature() -> void:
	assert_almost_eq(Spoilage.rate(20.0), 1.0, 1e-6)
	assert_almost_eq(Spoilage.rate(10.0), 0.5, 1e-6, "погреб (+10 °C) — вдвое медленнее")
	assert_lt(Spoilage.rate(-10.0), 0.13, "на морозе — почти не портится")
	assert_almost_eq(Spoilage.rate(10.0, true), 0.1, 1e-6, "ледник — ещё в 5 раз медленнее")
	assert_gt(Spoilage.rate(35.0), 2.0, "в жару — быстрее")


func test_age_in_steps_and_spoils() -> void:
	var def := Registry.item(&"raw_meat")   # 2 дня
	var s := ItemStack.create(def, 3)
	var total := 0.0
	for i in 48:
		Spoilage.age(s, def, 1.0, 1.0, rng)
	var f := Spoilage.freshness(s)
	assert_lte(f, 0.25, "за срок хранения при 20 °C — испортилось (ступени случайны, среднее — в отдельном тесте)")
	assert_eq(fmod(f * Spoilage.STEPS, 1.0), 0.0, "свежесть ступенями")
	var salt := Registry.item(&"salted_lard")
	var t := ItemStack.create(salt, 1)
	for i in 48:
		Spoilage.age(t, salt, 1.0, 1.0, rng)
	assert_gt(Spoilage.freshness(t), 0.9, "солёное за те же двое суток почти не изменилось")
	var stone := Registry.item(&"granite")
	var g := ItemStack.create(stone, 1)
	assert_false(Spoilage.age(g, stone, 100.0, 1.0, rng), "камень не портится")


func test_average_rate_is_exact() -> void:
	var def := Registry.item(&"bread_wheat") if Registry.item(&"bread_wheat") != null else Registry.item(&"wheat_bread")
	var sum := 0.0
	for k in 200:
		var s := ItemStack.create(def, 1)
		for i in 24:
			Spoilage.age(s, def, 0.5, 1.0, rng)   # 12 часов мелкими шагами
		sum += 1.0 - Spoilage.freshness(s)
	var expect := 12.0 / (float(def.food["spoil_days"]) * 24.0)
	assert_almost_eq(sum / 200.0, expect, 0.02, "в среднем — ровно по сроку хранения")


func test_container_catch_up() -> void:
	var world := World.new()
	world.setup(Registry, null, 7)
	var col := ChunkColumn.new(Vector2i(0, 0))
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, Registry.block_num(&"granite"))
	world.chunks.columns[Vector2i(0, 0)] = col
	var clock := GameClock.new(24.0)
	var sys := SpoilageSystem.new()
	sys.setup(world, clock, null, null, null, null)
	var p := Vector3i(2, 61, 2)
	world.set_block(p.x, p.y, p.z, Registry.block_num(&"chest_wood"))
	var e := { "items": [ItemStack.make(&"raw_meat", 4).to_dict()], "spoil_t": 0.0 }
	world.set_entity(p, e)
	sys.age_container(p, world.get_entity(p), 5.0 * 24.0 * 60.0)
	var s := ItemStack.from_dict(world.get_entity(p)["items"][0])
	assert_lt(Spoilage.freshness(s), 0.5, "за 5 дней в выгруженном сундуке мясо испортилось")
	sys.free()
	world.free()
