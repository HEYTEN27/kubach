extends GutTest
## Поверхность: снег копится и тает, вода замерзает и оттаивает, огонь и молния.

var world: World
var ticker: SurfaceTicker
var stone: int
var water: int


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 5)
	var col := ChunkColumn.new(Vector2i(0, 0))
	stone = Registry.block_num(&"granite")
	water = Registry.block_num(&"water")
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, stone)
	for z in 8:
		for x in 8:
			col.set_block(x + 8, 60, z + 8, water)
	world.chunks.columns[Vector2i(0, 0)] = col
	ticker = SurfaceTicker.new(world)
	ticker.rng.seed = 3


func after_each() -> void:
	world.free()


func test_snow_accumulates_and_melts() -> void:
	for i in 40:
		var y := 61 if world.get_block(2, 61, 2) != 0 else 60
		ticker.apply(2, y, 2, world.get_block(2, y, 2), -10.0, 1.0, 0.0, 1.0)
	var lvl := ticker.snow_level(world.get_block(2, 61, 2))
	assert_gte(lvl, 3, "снег копится слоями")
	assert_lte(lvl, 8)
	for i in 200:
		var b := world.get_block(2, 61, 2)
		if b == 0:
			break
		ticker.apply(2, 61, 2, b, 12.0, 0.0, 0.5, 1.0)
	assert_eq(world.get_block(2, 61, 2), 0, "в тепле растаял")


func test_light_neutral() -> void:
	assert_false(world.light_differs(0, Registry.block_num(&"snow_layer_4")), "снег не меняет свет")
	assert_false(world.light_differs(water, Registry.block_num(&"ice")))
	assert_true(world.light_differs(0, stone))


func test_freeze_and_thaw() -> void:
	for i in 50:
		ticker.apply(10, 60, 10, world.get_block(10, 60, 10), -12.0, 0.0, 0.0, 1.0)
	assert_eq(world.get_block(10, 60, 10), Registry.block_num(&"ice"))
	for i in 80:
		ticker.apply(10, 60, 10, world.get_block(10, 60, 10), 10.0, 0.0, 0.0, 1.0)
	assert_eq(world.get_block(10, 60, 10), water)


func test_tick_area() -> void:
	var n := 0
	for i in 30:
		n += ticker.tick(8.0, 8.0, { "snow": 1.0, "rain": 0.0 }, func(_x: int, _y: int, _z: int) -> float: return -8.0, 0.5)
	assert_gt(n, 0)
	assert_lte(ticker.MAX_CHANGES, 12)


func test_fire_spreads_and_rain_puts_out() -> void:
	var fs := FireSystem.new(world)
	fs.rng.seed = 11
	var log_b := Registry.block_num(&"oak_log")
	for x in range(1, 6):
		world.set_block(x, 61, 1, log_b)
	var at: Variant = fs.ignite(Vector3i(1, 61, 1))
	assert_not_null(at, "бревно загорелось")
	assert_eq(world.get_block(1, 62, 1), Registry.block_num(&"fire"))
	for i in 60:
		fs.tick(1.0)
	var logs := 0
	for x in range(1, 6):
		if world.get_block(x, 61, 1) == log_b:
			logs += 1
	assert_lt(logs, 5, "огонь пережёг брёвна")
	# Дождь тушит.
	for x in range(1, 6):
		world.set_block(x, 61, 3, log_b)
	fs.ignite(Vector3i(3, 61, 3))
	fs.tick(1.0, func(_p: Vector3i) -> bool: return true)
	assert_eq(fs.fires.size(), 0)
	assert_false(fs.ignite(Vector3i(1, 61, 9)) != null and world.get_block(1, 61, 9) == stone, "камень не горит")


func test_lightning_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var p := LightningTarget.pick(world, 8, 8, rng, 4)
	assert_gte(p.y, 60, "бьёт в поверхность")
	world.set_block(4, 70, 4, stone)   # высокий столб
	var hits := 0
	for i in 40:
		var q := LightningTarget.pick(world, 4, 4, rng, 2)
		if q == Vector3i(4, 70, 4):
			hits += 1
	assert_gt(hits, 5, "высокие точки притягивают молнию")
	var rod := Registry.block_num(&"lightning_rod")
	world.set_block(12, 61, 3, rod)
	var r := LightningTarget.pick(world, 8, 8, rng, 4, [Vector3i(12, 61, 3)])
	assert_eq(r, Vector3i(12, 61, 3), "громоотвод перехватывает")
