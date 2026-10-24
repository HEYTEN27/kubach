extends GutTest
## GameClock: ход времени по длине суток, смена дня, ночь, сезоны, формат времени.


func test_day_length() -> void:
	var c := GameClock.new(24.0)
	assert_almost_eq(c.hours_per_second(), 1.0 / 60.0, 1e-6, "24 мин сутки — игровой час за минуту")
	var h := c.advance(60.0)
	assert_almost_eq(h, 1.0, 1e-6)
	assert_almost_eq(c.hour(), 9.0, 1e-4)


func test_day_rollover_and_night() -> void:
	var c := GameClock.new(24.0)
	assert_false(c.is_night())
	c.advance_hours(14.0)   # 22:00
	assert_true(c.is_night())
	assert_eq(c.day, 1)
	c.advance_hours(3.0)    # 01:00
	assert_eq(c.day, 2)
	assert_true(c.is_night())
	assert_almost_eq(c.hours_until(6.0), 5.0, 1e-4)
	c.advance_hours(c.hours_until(6.0))
	assert_false(c.is_night())


func test_seasons() -> void:
	var c := GameClock.new()
	c.start_season = 1
	c.season_length = 7
	assert_eq(c.season(), &"summer")
	c.day = 8
	assert_eq(c.season(), &"autumn")
	assert_eq(c.season_day(), 1)
	c.day = 22
	assert_eq(c.season(), &"spring", "по кругу")


func test_time_text_and_save() -> void:
	var c := GameClock.new()
	c.minute = 14 * 60 + 5
	assert_eq(c.time_text(), "14:05")
	assert_eq(c.time_text(false), "2:05 PM")
	c.minute = 5
	assert_eq(c.time_text(false), "12:05 AM")
	c.day = 9
	var d := GameClock.new()
	d.from_dict(c.to_dict())
	assert_eq(d.day, 9)
	assert_almost_eq(d.minute, 5.0, 1e-4)
