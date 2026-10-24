extends GutTest

var gen: TerrainGenerator


func before_each() -> void:
	gen = TerrainGenerator.new(12345, Registry)


func _column_hash(col: ChunkColumn) -> int:
	var parts := []
	for si in col.sections.size():
		var s := col.sections[si]
		parts.append(si)
		if s == null:
			parts.append(-1)
		elif s.is_uniform():
			parts.append(s.uniform)
		else:
			parts.append(hash(s.blocks))
	return hash(parts)


func test_same_seed_same_world() -> void:
	var other := TerrainGenerator.new(12345, Registry)
	for cpos: Vector2i in [Vector2i(0, 0), Vector2i(-7, 3), Vector2i(900, -930)]:
		assert_eq(_column_hash(gen.generate_column(cpos)), _column_hash(other.generate_column(cpos)), str(cpos))


func test_generation_order_does_not_matter() -> void:
	var a1 := _column_hash(gen.generate_column(Vector2i(1, 1)))
	var b1 := _column_hash(gen.generate_column(Vector2i(40, -2)))
	var fresh := TerrainGenerator.new(12345, Registry)
	var b2 := _column_hash(fresh.generate_column(Vector2i(40, -2)))
	var a2 := _column_hash(fresh.generate_column(Vector2i(1, 1)))
	assert_eq(a1, a2)
	assert_eq(b1, b2)


func test_different_seed_differs() -> void:
	var other := TerrainGenerator.new(54321, Registry)
	var same := 0
	for i in 8:
		var cpos := Vector2i(i * 37, -i * 11)
		if _column_hash(gen.generate_column(cpos)) == _column_hash(other.generate_column(cpos)):
			same += 1
	assert_lt(same, 2)


func test_text_seed() -> void:
	assert_eq(WorldSeed.from_text("42"), 42)
	assert_eq(WorldSeed.from_text(" -7 "), -7)
	assert_eq(WorldSeed.from_text("тайга"), WorldSeed.from_text("тайга"))
	assert_ne(WorldSeed.from_text("тайга"), WorldSeed.from_text("Тайга"))


func test_bedrock_layer() -> void:
	var col := gen.generate_column(Vector2i(3, 4))
	var bedrock := Registry.block_num(&"bedrock")
	for y in range(-256, -249):
		assert_eq(col.get_block(7, y, 7), bedrock, "y=%d" % y)
	assert_ne(col.get_block(7, -249, 7), bedrock)


func test_surface_matches_height_and_water_fills_to_sea() -> void:
	var plain := _plain_gen()
	var water := Registry.block_num(&"water")
	var ice := Registry.block_num(&"ice")
	var checked := 0
	for i in 12:
		var cpos := Vector2i(i * 23 - 100, i * 17 - 60)
		var col := plain.generate_column(cpos)
		for p: Vector2i in [Vector2i(0, 0), Vector2i(8, 8), Vector2i(15, 3)]:
			var x := cpos.x * 16 + p.x
			var z := cpos.y * 16 + p.y
			var info := plain.surface_info(x, z)
			var h := info[0]
			var wl := info[1]
			assert_eq(Registry.block_solid[col.get_block(p.x, h, p.y)], 1, "поверхность на %d,%d твёрдая" % [x, z])
			if wl != TerrainGenerator.NO_WATER and h < wl:
				assert_true(col.get_block(p.x, wl, p.y) in [water, ice], "вода до уровня %d" % wl)
				assert_eq(Registry.block_solid[col.get_block(p.x, wl + 1, p.y)], 0)
			else:
				var above := Registry.block_by_num(col.get_block(p.x, h + 1, p.y))
				assert_true(not above.solid or above.has_tag("log") or above.has_tag("leaves") or above.material == &"stone",
					"над поверхностью не грунт: %s" % above.id)
			checked += 1
	assert_eq(checked, 36)


func _plain_gen(seed_value: int = 12345) -> TerrainGenerator:
	var st := WorldGenSettings.new()
	st.caves = 0.0
	st.ores = 0.0
	return TerrainGenerator.new(seed_value, Registry, st)


func test_sections_match_reference_fill() -> void:
	# Быстрая заливка по «прогонам» должна совпадать с поблочной проверкой высоты
	# (без пещер и руд; деревья — выше, поэтому «воздух» проверяем с запасом 50).
	var plain := _plain_gen()
	var cpos := Vector2i(-5, 9)
	var col := plain.generate_column(cpos)
	for lz: int in [0, 7, 15]:
		for lx: int in [0, 9, 15]:
			var info := plain.surface_info(cpos.x * 16 + lx, cpos.y * 16 + lz)
			var h := info[0]
			for y in range(-256, 320, 3):
				var b := col.get_block(lx, y, lz)
				if y <= h:
					assert_ne(b, 0, "твёрдо ниже поверхности y=%d" % y)
				elif y > maxi(h, plain.sea_level) + 50:
					assert_eq(b, 0, "воздух выше y=%d" % y)


func test_deep_sections_are_uniform() -> void:
	var col := _plain_gen().generate_column(Vector2i(0, 0))
	var uniform := 0
	for s in col.sections:
		if s != null and s.is_uniform():
			uniform += 1
	assert_gt(uniform, 4, "глубинный слой должен храниться одним числом")


func test_section_flags_set_by_generation() -> void:
	var col := gen.generate_column(Vector2i(2, 2))
	for si in col.sections.size():
		var s := col.sections[si]
		if s == null:
			continue
		var real := ChunkSection.new()
		real.uniform = s.uniform
		real.blocks = s.blocks
		real.analyze(Registry.block_opaque, Registry.block_shape)
		if s.all_opaque:
			assert_true(real.all_opaque, "all_opaque не должен врать (секция %d)" % si)
		if real.has_special:
			assert_true(s.has_special, "has_special обязан быть выставлен (секция %d)" % si)


func test_geology_layers_by_depth() -> void:
	var col := _plain_gen().generate_column(Vector2i(10, 10))
	var deepslate := Registry.block_num(&"deepslate")
	assert_eq(col.get_block(8, -200, 8), deepslate, "глубже −120 — глубинный сланец")
	var mid := Registry.block_by_num(col.get_block(8, -20, 8))
	assert_true(mid.has_tag("stone"), "на −20 — порода, а не %s" % mid.id)
