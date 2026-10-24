extends GutTest
## Настройки мира с экрана создания (раздел 2.2).


func test_settings_roundtrip_and_clamp() -> void:
	var s := WorldGenSettings.from_dict({ "world_type": "archipelago", "caves": 5.0, "sea_level": 10, "season_length": 3,
		"difficulty": "hardcore", "start_season": "winter" })
	assert_eq(s.world_type, &"archipelago")
	assert_eq(s.caves, 3.0, "ограничение сверху")
	assert_eq(s.sea_level, 32, "ограничение снизу")
	assert_eq(s.season_length, 7)
	assert_eq(s.difficulty, &"hardcore")
	assert_eq(s.season_index(), 3)
	var back := WorldGenSettings.from_dict(s.to_dict())
	assert_eq(back.to_dict(), s.to_dict())


func test_defaults_match_spec() -> void:
	var s := WorldGenSettings.new()
	assert_eq(s.season_length, 28)
	assert_eq(s.day_length, 24)
	assert_eq(s.sea_level, 64)


func test_flat_world() -> void:
	var s := WorldGenSettings.new()
	s.world_type = &"flat"
	var g := TerrainGenerator.new(1, Registry, s)
	for i in 20:
		assert_eq(g.surface_height(i * 97 - 900, i * 31), 65, "плоский мир")


func test_sea_level_slider() -> void:
	var s := WorldGenSettings.new()
	s.sea_level = 50
	var g := TerrainGenerator.new(5, Registry, s)
	assert_eq(g.sea_level, 50)
	var water := Registry.block_num(&"water")
	for i in 40:
		var info := g.surface_info(i * 211 - 4000, i * 97)
		if info[1] == 50 and info[0] < 45:
			var col := g.generate_column(Vector2i((i * 211 - 4000) >> 4, (i * 97) >> 4))
			assert_eq(col.get_block((i * 211 - 4000) & 15, 50, (i * 97) & 15), water)
			return
	fail_test("не нашли море")


func test_world_types_loaded() -> void:
	for id in [&"normal", &"large_biomes", &"archipelago", &"mountainous", &"flat"]:
		assert_false(Registry.get_entry("world_types", id).is_empty(), String(id))


func test_large_biomes_are_larger() -> void:
	var normal := TerrainGenerator.new(9, Registry)
	var s := WorldGenSettings.new()
	s.world_type = &"large_biomes"
	var large := TerrainGenerator.new(9, Registry, s)
	assert_lt(_changes(large), _changes(normal), "смен биома вдоль линии меньше")


func _changes(g: TerrainGenerator) -> int:
	var n := 0
	var prev := -1
	for x in range(-8000, 8000, 32):
		var b := g.grid_biome(x, 300)
		if b != prev:
			n += 1
			prev = b
	return n


func test_save_stores_settings() -> void:
	var s := WorldGenSettings.new()
	s.world_type = &"mountainous"
	s.ores = 2.0
	var ws := WorldSave.create("настройки", "1", &"survival", "user://test_settings_saves", s)
	var again := WorldSave.open(ws.folder)
	assert_eq(again.gen_settings().world_type, &"mountainous")
	assert_eq(again.gen_settings().ores, 2.0)
	DirAccess.remove_absolute(ws.region_dir())
	DirAccess.remove_absolute(ws.folder.path_join("world.json"))
	DirAccess.remove_absolute(ws.folder)
	DirAccess.remove_absolute("user://test_settings_saves")
