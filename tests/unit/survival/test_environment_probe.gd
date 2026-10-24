extends GutTest
## EnvironmentProbe: температура воздуха (биом, сезон, сутки, высота, укрытие, вода),
## тепло костров, контакт с лавой.

var cfg: Dictionary


func before_each() -> void:
	cfg = Registry.get_entry("survival", &"default")


func test_season_and_daytime() -> void:
	var summer_day := EnvironmentProbe.air_temperature(cfg, 10.0, &"summer", 15.0, 70.0, 64.0, 15, false)
	assert_almost_eq(summer_day, 12.0, 0.01, "лето +2, 15:00 — без ночного холода")
	var winter_night := EnvironmentProbe.air_temperature(cfg, 10.0, &"winter", 3.0, 70.0, 64.0, 15, false)
	assert_almost_eq(winter_night, 10.0 - 18.0 - 5.0, 0.01)


func test_altitude_shelter_water() -> void:
	var high := EnvironmentProbe.air_temperature(cfg, 10.0, &"summer", 15.0, 64.0 + 16.0 + 100.0, 64.0, 15, false)
	assert_almost_eq(high, 12.0 - 6.0, 0.01, "−0,6 °C на 10 блоков")
	var cave := EnvironmentProbe.air_temperature(cfg, -20.0, &"winter", 3.0, 20.0, 64.0, 0, false)
	assert_almost_eq(cave, 10.0, 0.01, "под землёй постоянные +10")
	var swim := EnvironmentProbe.air_temperature(cfg, 10.0, &"summer", 15.0, 64.0, 64.0, 15, true)
	assert_almost_eq(swim, 12.0 - 8.0, 0.01)


func test_heat_falloff() -> void:
	assert_almost_eq(EnvironmentProbe.heat_falloff(18.0, 0.0, 7.0), 18.0, 0.01)
	assert_gt(EnvironmentProbe.heat_falloff(18.0, 2.0, 7.0), 10.0, "у костра тепло")
	assert_lt(EnvironmentProbe.heat_falloff(18.0, 6.5, 7.0), 2.0)
	assert_eq(EnvironmentProbe.heat_falloff(18.0, 8.0, 7.0), 0.0)


func test_heat_around_and_sample() -> void:
	var world := World.new()
	world.setup(Registry, null, 5)
	var col := ChunkColumn.new(Vector2i(0, 0))
	var stone := Registry.block_num(&"granite")
	for z in 16:
		for x in 16:
			col.set_block(x, 63, z, stone)
	col.set_block(6, 64, 4, Registry.block_num(&"campfire"))
	col.set_block(2, 64, 2, Registry.block_num(&"lava"))
	world.chunks.columns[Vector2i(0, 0)] = col
	var clock := GameClock.new()
	var probe := EnvironmentProbe.new(world, cfg)
	var near := probe.sample(4.5, 64.0, 4.5, 65.6, clock)
	var far := probe.sample(13.5, 64.0, 13.5, 65.6, clock)
	assert_gt(float(near["heat"]), 5.0, "костёр в двух блоках")
	assert_lt(float(far["heat"]), 1.0)
	assert_eq(float(near["contact_damage"]), 0.0)
	var in_lava := probe.sample(2.5, 64.0, 2.5, 65.6, clock)
	assert_eq(float(in_lava["contact_damage"]), 40.0)
	assert_false(in_lava["in_water"], "лава — не вода")
	assert_eq(probe.sky_exposure(10.5, 65.6, 10.5), 15, "под открытым небом")
	for z in range(6, 15):
		for x in range(6, 15):
			col.set_block(x, 70, z, stone)
	assert_eq(probe.sky_exposure(10.5, 65.6, 10.5), 0, "под крышей")
	assert_lt(float(probe.sample(10.5, 64.0, 10.5, 65.6, clock)["sky"]), 1.0)
	world.free()
