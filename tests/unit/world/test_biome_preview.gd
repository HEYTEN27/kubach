extends GutTest


func test_preview_is_deterministic_and_colored() -> void:
	var a := BiomePreview.new(TerrainGenerator.new(77, Registry)).render_now(32)
	var b := BiomePreview.new(TerrainGenerator.new(77, Registry)).render_now(32)
	assert_eq(a.get_size(), Vector2i(32, 32))
	assert_eq(a.get_data(), b.get_data(), "одинаковый сид — одинаковая карта")
	var colors := {}
	for y in 32:
		for x in 32:
			colors[a.get_pixel(x, y).to_html()] = true
	assert_gt(colors.size(), 5, "на карте несколько биомов")


func test_different_seed_different_map() -> void:
	var a := BiomePreview.new(TerrainGenerator.new(1, Registry)).render_now(16)
	var b := BiomePreview.new(TerrainGenerator.new(2, Registry)).render_now(16)
	assert_ne(a.get_data(), b.get_data())


func test_threaded_levels_complete() -> void:
	var p := BiomePreview.new(TerrainGenerator.new(3, Registry))
	var sizes: Array[int] = []
	p.level_ready.connect(func(_img: Image, size: int) -> void: sizes.append(size))
	p.start()
	var deadline := Time.get_ticks_msec() + 60000
	while sizes.size() < 2 and Time.get_ticks_msec() < deadline:
		p.poll()
		OS.delay_msec(5)
	p.cancel()
	assert_eq(sizes.slice(0, 2), [64, 128], "уровни детализации по нарастающей")
