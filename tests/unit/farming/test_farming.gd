extends GutTest
## Ферма (этап 9): рост по условиям, стадии, урожай, гибриды; грядка, посадка, полив, сорняки,
## увядание, теплица, досчёт за время отсутствия.

var world: World
var farm: FarmSystem
var clock: GameClock
var loam: int
var stone: int


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 41)
	loam = Registry.block_num(&"loam")
	stone = Registry.block_num(&"granite")
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
					col.set_block(x, 61, z, loam)
			world.chunks.columns[Vector2i(cx, cz)] = col
	clock = GameClock.new(24.0)
	clock.start_season = 1   # лето
	clock.season_length = 28
	clock.minute = 12 * 60.0
	farm = FarmSystem.new()
	farm.setup(world, clock, PlayerVitals.from_registry(Registry, &"normal").cfg)


func after_each() -> void:
	farm.free()
	world.free()


func _wheat() -> Dictionary:
	return Registry.get_entry("crops", &"wheat")


func test_crops_from_data() -> void:
	assert_gte(Registry.crop_ids.size(), 40, "40+ культур")
	assert_true(Registry.block_num(&"crop_wheat_0") > 0, "блоки стадий выведены из crops.json")
	assert_not_null(Registry.item(&"wheat_seeds"), "семена тоже")
	assert_eq(Registry.item(&"wheat_seeds").plant, &"wheat")
	var b := Registry.block_num(&"crop_tomato_4")
	assert_eq(Registry.crop_ids[Registry.block_crop[b] - 1], &"tomato")
	assert_eq(Registry.block_crop_stage[b], 4)


func test_growth_rate_conditions() -> void:
	var c := _wheat()
	var good := { "season": "summer", "temp": 18.0, "wet": true }
	var r := CropGrowth.rate_per_hour(c, good)
	assert_almost_eq(r, 1.0 / (7.0 * 24.0), 1e-6, "в хороших условиях — за grow_days")
	var dry := good.duplicate()
	dry["wet"] = false
	assert_lt(CropGrowth.rate_per_hour(c, dry), r, "на сухой грядке медленнее")
	var fert := good.duplicate()
	fert["fert"] = 1.0
	assert_gt(CropGrowth.rate_per_hour(c, fert), r, "удобрение ускоряет")
	var weeds := good.duplicate()
	weeds["weeds"] = 3
	assert_lt(CropGrowth.rate_per_hour(c, weeds), r, "сорняки мешают")
	var winter := good.duplicate()
	winter["season"] = "winter"
	assert_eq(CropGrowth.rate_per_hour(c, winter), 0.0, "зимой не растёт")
	winter["greenhouse"] = true
	assert_gt(CropGrowth.rate_per_hour(c, winter), 0.0, "в теплице растёт и зимой")
	var cold := good.duplicate()
	cold["temp"] = -2.0
	assert_eq(CropGrowth.rate_per_hour(c, cold), 0.0, "в мороз не растёт")
	var dark := good.duplicate()
	dark["dark"] = true
	assert_eq(CropGrowth.rate_per_hour(c, dark), 0.0, "без света не растёт")
	var rice := Registry.get_entry("crops", &"rice")
	assert_eq(CropGrowth.rate_per_hour(rice, good), 0.0, "рис — только у воды")
	good["near_water"] = true
	assert_gt(CropGrowth.rate_per_hour(rice, good), 0.0)


func test_stage_and_wither() -> void:
	assert_eq(CropGrowth.stage_of(0.0, 5), 0)
	assert_eq(CropGrowth.stage_of(0.99, 5), 3, "спелая — только при полном созревании")
	assert_eq(CropGrowth.stage_of(1.0, 5), 4)
	var e := { "p": 0.5 }
	var c := _wheat()
	var bad := { "season": "winter", "temp": 18.0, "wet": true }
	assert_eq(CropGrowth.advance(e, c, bad, 24.0), "")
	assert_eq(CropGrowth.advance(e, c, bad, 60.0), "wither", "однолетник вянет вне сезона")
	var bush := Registry.get_entry("crops", &"currant")
	var eb := { "p": 0.5 }
	assert_eq(CropGrowth.advance(eb, bush, bad, 400.0), "", "многолетник зимой спит, а не вянет")


func test_harvest_drops_and_hybrid() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var c := _wheat()
	var drops := CropGrowth.harvest(c, 4, rng)
	assert_eq(drops[0][0], &"wheat", "урожай")
	assert_eq(drops[1][0], &"wheat_seeds", "и семена")
	assert_eq(CropGrowth.harvest(c, 2, rng), [[&"wheat_seeds", 1]], "незрелое — семя назад")
	var got_hybrid := false
	for i in 300:
		for d: Array in CropGrowth.harvest(c, 4, rng, &"rye"):
			if d[0] == &"triticale_seeds":
				got_hybrid = true
	assert_true(got_hybrid, "пшеница рядом с рожью изредка даёт тритикале")


func test_till_plant_grow_harvest() -> void:
	var g := Vector3i(3, 61, 3)
	assert_true(farm.till(g), "мотыга превращает почву в грядку")
	assert_eq(world.get_block(3, 61, 3), Registry.block_num(&"farmland"))
	var p := g + Vector3i.UP
	assert_true(farm.plant(p, &"radish"))
	assert_eq(world.get_block(p.x, p.y, p.z), Registry.block_num(&"crop_radish_0"))
	assert_false(farm.plant(Vector3i(5, 61, 5), &"radish"), "не на грядку — нельзя")
	farm.water(p)
	# Три дня спустя (редис растёт 3 дня в сезон весна/осень): ставим осень.
	clock.start_season = 2
	var t := clock.total_minutes()
	farm.update_crop(p, t + 4 * 24 * 60.0)
	var b := world.get_block(p.x, p.y, p.z)
	assert_eq(b, Registry.block_num(&"crop_radish_4"), "созрел")
	assert_eq(world.get_entity(p)["type"], "crop", "сущность пережила смену блока")
	assert_true(farm.harvest(p), "спелое собирается ПКМ")
	assert_eq(world.get_block(p.x, p.y, p.z), Registry.block_num(&"crop_radish_0"), "однолетник пересажен")


func test_greenhouse_and_dark() -> void:
	var p := Vector3i(6, 62, 6)
	farm.till(p + Vector3i.DOWN)
	farm.plant(p, &"lettuce")
	var e := world.get_entity(p)
	assert_eq(int(farm._roof(p)), 0, "над грядкой небо")
	world.set_block(p.x, p.y + 4, p.z, Registry.block_num(&"glass"))
	assert_true(farm.conditions(p, e)["greenhouse"], "стекло сверху — теплица")
	world.set_block(p.x, p.y + 3, p.z, stone)
	assert_true(farm.conditions(p, e)["dark"], "крыша — темно")


func test_water_near_and_wither_block() -> void:
	var p := Vector3i(8, 62, 8)
	farm.till(p + Vector3i.DOWN)
	farm.plant(p, &"cabbage")
	var e := world.get_entity(p)
	assert_false(farm.conditions(p, e)["wet"], "сухо")
	world.set_block(p.x + 3, 61, p.z, Registry.block_num(&"water"))
	assert_true(farm.conditions(p, e)["wet"], "вода в 4 блоках поливает")
	# Зима: однолетник вянет.
	clock.start_season = 3
	farm.update_crop(p, clock.total_minutes() + 10 * 24 * 60.0)
	assert_eq(world.get_block(p.x, p.y, p.z), Registry.block_num(&"withered_crop"))
	assert_false(farm.crops.has(p))


func test_weeds_spread_on_farmland() -> void:
	var p := Vector3i(10, 62, 10)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			farm.till(Vector3i(p.x + dx, 61, p.z + dz))
	farm.plant(p, &"potato")
	for i in 40:
		farm._spread_weeds(p, 24.0)
	assert_gt(farm._weeds_around(p), 0, "на пустых грядках рядом заводятся сорняки")
