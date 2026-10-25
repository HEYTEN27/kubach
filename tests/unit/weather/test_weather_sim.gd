extends GutTest
## Погода: детерминизм по сиду, ограничения климата, сезоны, переход, дождь ↔ снег, сохранение.


func _sim(seed_v: int = 7) -> WeatherSim:
	return WeatherSim.new(Registry, seed_v)


func test_deterministic() -> void:
	var a := _sim(42)
	var b := _sim(42)
	var climate := { "weather": ["rain", "fog", "snow"], "season": "autumn", "temp": 6.0 }
	var seq_a := []
	var seq_b := []
	for i in 30:
		a.advance(3.0, climate)
		b.advance(3.0, climate)
		seq_a.append(a.current)
		seq_b.append(b.current)
	assert_eq(seq_a, seq_b)
	var c := _sim(43)
	var seq_c := []
	for i in 30:
		c.advance(3.0, climate)
		seq_c.append(c.current)
	assert_ne(seq_a, seq_c, "другой сид — другая погода")


func test_climate_limits() -> void:
	var s := _sim()
	var desert := s.allowed_weights({ "weather": ["dry_wind"], "season": "summer", "temp": 32.0 })
	assert_false(desert.has(&"snow"), "в жару снега нет")
	assert_false(desert.has(&"rain"), "в пустыне без ключа rain — без дождя")
	assert_true(desert.has(&"dry_wind"))
	var taiga_winter := s.allowed_weights({ "weather": ["rain", "fog", "snow"], "season": "winter", "temp": -15.0 })
	assert_true(taiga_winter.has(&"snow"))
	assert_false(taiga_winter.has(&"thunderstorm"), "грозы в мороз нет")
	var summer := s.allowed_weights({ "weather": ["rain", "thunderstorm"], "season": "summer", "temp": 20.0 })
	assert_true(summer.has(&"thunderstorm"))
	assert_false(summer.has(&"snow"), "летом снег не выбирается")
	var any := s.allowed_weights({ "weather": [], "season": "autumn", "temp": -5.0 })
	assert_true(any.has(&"snow"), "в мороз снег возможен везде")


func test_rain_becomes_snow_and_blend() -> void:
	var s := _sim()
	s.force(&"rain")
	var cold := s.values(-5.0)
	assert_eq(float(cold["rain"]), 0.0)
	assert_gt(float(cold["snow"]), 0.3, "дождь в мороз идёт снегом")
	var warm := s.values(10.0)
	assert_gt(float(warm["rain"]), 0.3)
	s.previous = &"clear"
	s.current = &"downpour"
	s.since_hours = 0.0
	assert_almost_eq(float(s.values(10.0)["rain"]), 0.0, 0.001, "переход начинается с прошлой погоды")
	s.since_hours = 1.0
	assert_almost_eq(float(s.values(10.0)["rain"]), 1.0, 0.001)


func test_changes_over_time_and_save() -> void:
	var s := _sim(5)
	var climate := { "weather": ["rain", "thunderstorm", "fog"], "season": "summer", "temp": 18.0 }
	var seen := {}
	for i in 200:
		s.advance(2.0, climate)
		seen[s.current] = true
	assert_gte(seen.size(), 4, "погода меняется")
	var d := JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary
	var t := _sim(5)
	t.from_dict(d)
	assert_eq(t.current, s.current)
	assert_almost_eq(t.left_hours, s.left_hours, 0.0001)
	var v := t.values(18.0)
	assert_between(float(v["wind"]), 0.0, 1.0)
	assert_true(v["wind_dir"] is Vector2)
