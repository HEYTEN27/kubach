extends GutTest
## Небо: длина дня по сезонам, дуга солнца, фазы и восход луны, часы.

var windows: Array


func before_all() -> void:
	windows = SkyMath.season_windows(Registry)


func test_seasons_loaded() -> void:
	assert_eq(windows.size(), 4)


func test_day_length_by_season() -> void:
	var summer := SkyMath.day_window(0.375, windows)   # середина лета
	var winter := SkyMath.day_window(0.875, windows)   # середина зимы
	assert_almost_eq(summer.x, 4.5, 0.01)
	assert_almost_eq(winter.y, 16.5, 0.01)
	assert_gt(summer.y - summer.x, winter.y - winter.x + 8.0, "летний день намного длиннее")
	# Плавно: на границе сезонов — среднее соседних.
	var border := SkyMath.day_window(0.5, windows)
	assert_almost_eq(border.x, (4.5 + 6.5) / 2.0, 0.01)


func test_sun_arc() -> void:
	var w := Vector2(5.0, 21.0)
	assert_almost_eq(SkyMath.sun(5.0, w).x, 0.0, 0.01, "восход на горизонте")
	assert_gt(SkyMath.sun(13.0, w).x, 50.0, "длинный день — солнце высоко")
	assert_lt(SkyMath.sun(1.0, w).x, 0.0, "ночью под горизонтом")
	var short := Vector2(8.5, 16.5)
	assert_lt(SkyMath.sun(12.5, short).x, 30.0, "зимой низко")
	assert_almost_eq(SkyMath.sun(13.0, w).y, 180.0, 0.01, "в полдень на юге")
	var d := SkyMath.direction(Vector2(0.0, 90.0))
	assert_almost_eq(d.x, 1.0, 0.001, "восток — +X")


func test_moon() -> void:
	assert_almost_eq(SkyMath.moon_illumination(0.5), 1.0, 0.001)
	assert_almost_eq(SkyMath.moon_illumination(0.0), 0.0, 0.001)
	var p1 := SkyMath.moon_phase(1, 0.0, 8.0)
	var p5 := SkyMath.moon_phase(5, 0.0, 8.0)
	assert_almost_eq(absf(p5 - p1), 0.5, 0.001, "через полцикла — противоположная фаза")
	var w := Vector2(6.0, 20.0)
	# Полная луна восходит на закате солнца и стоит высоко в полночь.
	assert_gt(SkyMath.moon(1.0, w, 0.5).x, 20.0)
	assert_lt(SkyMath.moon(13.0, w, 0.5).x, 0.0)


func test_clock_uses_windows() -> void:
	var c := GameClock.new()
	c.windows = windows
	c.start_season = 3
	c.season_length = 10
	c.day = 5
	c.minute = 17.5 * 60.0
	assert_true(c.is_night(), "зимой в 17:30 уже ночь")
	c.start_season = 1
	assert_false(c.is_night(), "летом в 17:30 день")
	assert_lt(c.sunrise(), 6.0)
