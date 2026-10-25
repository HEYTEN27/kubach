extends GutTest
## Погода в игре: влияние на выживание, костёр под дождём, текст HUD, канал молнии,
## снег замедляет, сезонные окна дня из данных.


func test_weather_in_survival_env() -> void:
	var w := { "rain": 0.8, "snow": 0.0, "hail": 1.0, "hail_damage": 1.5, "temp": -3.0, "wind": 0.5, "thirst": 1.5 }
	var out := { "ambient": 15.0, "sky": 15 }
	SurvivalController.apply_weather(out, w)
	assert_almost_eq(float(out["rain"]), 0.8, 0.001, "под открытым небом дождь мочит")
	assert_almost_eq(float(out["hail"]), 1.5, 0.001, "град ранит")
	assert_lt(float(out["ambient"]), 15.0 - 3.0, "непогода и ветер холодят")
	assert_almost_eq(float(out["thirst_weather"]), 1.5, 0.001)
	var inside := { "ambient": 15.0, "sky": 0 }
	SurvivalController.apply_weather(inside, w)
	assert_eq(float(inside["rain"]), 0.0, "под крышей сухо")
	assert_eq(float(inside["hail"]), 0.0)
	assert_gt(float(inside["ambient"]), float(out["ambient"]), "в доме теплее")
	assert_almost_eq(float(inside["thirst_weather"]), 1.0, 0.001)


func test_hail_and_dry_wind_in_vitals() -> void:
	var v := PlayerVitals.from_registry(Registry, &"normal")
	var hp := v.health
	v.tick(1.0, 0.0, { "ambient": 18.0, "hail": 2.0 })
	assert_lt(v.health, hp, "град отнимает здоровье")
	var a := PlayerVitals.from_registry(Registry, &"normal")
	var b := PlayerVitals.from_registry(Registry, &"normal")
	a.tick(1.0, 2.0, { "ambient": 20.0 })
	b.tick(1.0, 2.0, { "ambient": 20.0, "thirst_weather": 1.5 })
	assert_lt(b.thirst, a.thirst, "суховей сушит быстрее")


func test_campfire_doused_by_rain() -> void:
	var data := CraftingData.shared(Registry)
	var dry := Station.new(data, &"campfire")
	var wet := Station.new(data, &"campfire")
	for st: Station in [dry, wet]:
		st.auto = false
		st.fuel.set_stack(0, ItemStack.make(&"oak_log", 4))
	wet.rain = 1.0
	dry.advance(20.0)
	wet.advance(20.0)
	var left_dry := _fuel_count(dry)
	var left_wet := _fuel_count(wet)
	assert_lt(left_wet, left_dry, "под дождём костёр прогорает быстрее")
	assert_lte(wet.temp, dry.temp, "и жар ниже")


func _fuel_count(st: Station) -> float:
	var s := st.fuel.get_stack(0)
	return (s.count if s != null else 0) + st.fuel_left / 100.0


func test_weather_hud_text() -> void:
	var t := Hud.weather_text("Дождь", { "wind": 0.5, "wind_dir": Vector2(0, 1) })
	assert_eq(t, "Дождь · ветер С 8 м/с", "ветер дует на юг — значит, северный")
	assert_eq(Hud.weather_text("Ясно", { "wind": 0.0 }), "Ясно · штиль")


func test_bolt_points_branching() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var pts := WeatherEffects.bolt_points(Vector3(0, 150, 0), Vector3(0, 60, 0), rng, 5, 0.2)
	assert_eq(pts.size(), 33, "2^5 отрезков")
	assert_eq(pts[0], Vector3(0, 150, 0))
	assert_eq(pts[pts.size() - 1], Vector3(0, 60, 0), "канал заканчивается в точке удара")
	for p in pts:
		assert_lt(absf(p.x), 40.0, "канал не разлетается в стороны")


func test_season_windows_from_data() -> void:
	var win := SkyMath.season_windows(Registry)
	assert_eq(win.size(), 4)
	var summer: Vector2 = win[1]
	var winter: Vector2 = win[3]
	assert_gt(summer.y - summer.x, winter.y - winter.x + 4.0, "летом день намного длиннее")


func test_snow_slows_player() -> void:
	var world := World.new()
	world.setup(Registry, null, 7)
	var col := ChunkColumn.new(Vector2i(0, 0))
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, Registry.block_num(&"granite"))
	col.set_block(4, 61, 4, Registry.block_num(&"snow_layer_6"))
	world.chunks.columns[Vector2i(0, 0)] = col
	var p := Player.new()
	p.setup(world, 4.5, 61.0, 4.5)
	assert_gt(p.wade(), 0.3, "в глубоком снегу вязнешь")
	p.body.set_position(8.5, 61.0, 8.5)
	assert_eq(p.wade(), 0.0)
	p.free()
	world.free()
