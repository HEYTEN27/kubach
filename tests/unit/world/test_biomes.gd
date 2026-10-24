extends GutTest
## Биомы (раздел 2.4): количество, тайга в пяти вариантах, встречаемость, плавные переходы.

const TAIGA := [&"taiga", &"snowy_taiga", &"old_growth_taiga", &"mountain_taiga", &"taiga_swamp"]

var gen: TerrainGenerator


func before_all() -> void:
	gen = TerrainGenerator.new(12345, Registry)


func test_at_least_28_biomes_with_all_taiga_variants() -> void:
	assert_gte(gen.biomes.count, 28)
	for id in TAIGA:
		assert_gte(gen.biomes.index_of(id), 0, "есть биом %s" % id)


func test_every_biome_has_complete_data() -> void:
	for i in gen.biomes.count:
		var d: Dictionary = gen.biomes.defs[i]
		assert_gt(gen.biomes.top[i], 0, "%s: верхний блок" % d["id"])
		assert_ne(String(d["ambience"]), "", "%s: звуки окружения" % d["id"])
		assert_ne(String(d["music"]), "", "%s: музыкальный набор" % d["id"])
		for season in 4:
			assert_ne(gen.biomes.palette(i, season, false), Color(0, 0, 0, 0))


func test_taiga_variants_and_most_biomes_occur() -> void:
	var seen := {}
	for gz in range(-8000, 8000, 160):
		for gx in range(-8000, 8000, 160):
			seen[gen.biomes.ids[gen.grid_biome(gx, gz)]] = true
	for id in TAIGA:
		assert_true(seen.has(id), "%s встречается в мире 16 000 × 16 000" % id)
	assert_gte(seen.size(), 30, "встречено биомов: %d — %s" % [seen.size(), seen.keys()])


func test_biome_selection_is_deterministic() -> void:
	var other := TerrainGenerator.new(12345, Registry)
	for i in 50:
		var x := i * 397 - 9000
		var z := i * -211 + 4000
		assert_eq(gen.biome_index_at(x, z), other.biome_index_at(x, z))


func test_colors_blend_smoothly_between_columns() -> void:
	# Узел сетки цветов на общем крае двух соседних колонн совпадает — шва нет.
	for i in 6:
		var a := gen.generate_column(Vector2i(i * 3 - 7, 2))
		var b := gen.generate_column(Vector2i(i * 3 - 6, 2))
		for ch in 8:
			for tz in 5:
				var ca := a.tints[ch * 25 + tz * 5 + 4]
				var cb := b.tints[ch * 25 + tz * 5 + 0]
				assert_almost_eq(ca.r, cb.r, 0.001)
				assert_almost_eq(ca.g, cb.g, 0.001)


func test_blend_radius_softens_borders() -> void:
	# Между соседними узлами (4 блока) цвет меняется не скачком: максимум — доля разницы палитр.
	var max_step := 0.0
	for i in 20:
		var col := gen.generate_column(Vector2i(i * 7 - 50, -i * 5))
		for tz in 5:
			for tx in 4:
				var c0 := col.tints[2 + tz * 5 + tx]
				var c1 := col.tints[2 + tz * 5 + tx + 1]
				max_step = maxf(max_step, absf(c0.g - c1.g) + absf(c0.r - c1.r))
	assert_lt(max_step, 0.25, "цвета травы меняются плавно")


func test_surface_follows_biome() -> void:
	var desert := gen.biomes.index_of(&"sand_desert")
	var sandy := [&"sand", &"sandstone", &"silica_sand", &"rock_salt", &"cactus"]
	for r in range(0, 6000, 32):
		for i in maxi(1, r / 8):
			var a := TAU * i / maxi(1, r / 8)
			var x := roundi(cos(a) * r)
			var z := roundi(sin(a) * r)
			var info := gen.surface_info(x, z)
			if info[2] != desert or info[1] != TerrainGenerator.NO_WATER:
				continue
			var col := gen.generate_column(Vector2i(x >> 4, z >> 4))
			var top := Registry.block_by_num(col.get_block(x & 15, info[0], z & 15))
			assert_true(top.id in sandy, "в пустыне песок, а не %s" % top.id)
			return
	fail_test("не нашли пустыню")
