extends GutTest
## Растительность: деревья в лесах, нет деревьев в океане, крона через границу колонн.

var gen: TerrainGenerator


func before_all() -> void:
	gen = TerrainGenerator.new(12345, Registry)


func _logs(col: ChunkColumn) -> int:
	var n := 0
	for y in range(-60, 200):
		for z in 16:
			for x in 16:
				var b := col.get_block(x, y, z)
				if b > 0 and Registry.block_by_num(b).has_tag("log"):
					n += 1
	return n


func _find_biome(id: StringName) -> Vector2i:
	var b := gen.biomes.index_of(id)
	for r in range(0, 6000, 32):
		for i in maxi(1, r / 8):
			var a := TAU * i / maxi(1, r / 8)
			var x := roundi(cos(a) * r)
			var z := roundi(sin(a) * r)
			if gen.biome_index_at(x, z) == b and gen.biome_index_at(x + 24, z + 24) == b:
				return Vector2i(x >> 4, z >> 4)
	return Vector2i(1 << 20, 0)


func test_taiga_has_trees() -> void:
	var c := _find_biome(&"taiga")
	assert_ne(c.x, 1 << 20, "нашли тайгу")
	var total := 0
	for dz in 3:
		for dx in 3:
			total += _logs(gen.generate_column(c + Vector2i(dx, dz)))
	assert_gt(total, 20, "в тайге растут деревья")


func test_steppe_is_treeless() -> void:
	var c := _find_biome(&"steppe")
	assert_ne(c.x, 1 << 20)
	assert_lt(_logs(gen.generate_column(c)), 30, "в степи почти нет деревьев")


func test_plants_on_surface() -> void:
	var c := _find_biome(&"meadow")
	var col := gen.generate_column(c)
	var plants := 0
	for z in 16:
		for x in 16:
			for y in range(40, 160):
				var b := col.get_block(x, y, z)
				if b > 0 and Registry.block_shape[b] == BlockDef.SHAPE_CROSS:
					plants += 1
	assert_gt(plants, 20, "на лугу трава и цветы")


func test_canopy_crosses_column_border() -> void:
	# Ствол у восточного края колонны A → в колонне B (x+1) рядом есть листва этого дерева.
	var c := _find_biome(&"mixed_forest")
	var found := 0
	for i in 12:
		var a_pos := c + Vector2i(i % 4, i / 4)
		var a := gen.generate_column(a_pos)
		var b := gen.generate_column(a_pos + Vector2i(1, 0))
		for z in range(2, 14):
			for y in range(40, 200):
				var blk := a.get_block(15, y, z)
				if blk <= 0 or not Registry.block_by_num(blk).has_tag("log"):
					continue
				# Наверху ствола (над ним листва) — проверяем соседа.
				var top := a.get_block(15, y + 1, z)
				if top <= 0 or not Registry.block_by_num(top).has_tag("leaves"):
					continue
				var leaves := 0
				for dy in range(-2, 3):
					for dz in range(-1, 2):
						var nb := b.get_block(0, y + dy, z + dz)
						if nb > 0 and Registry.block_by_num(nb).has_tag("leaves"):
							leaves += 1
				assert_gt(leaves, 0, "крона дерева у края колонны продолжается в соседней")
				found += 1
				break
	assert_gt(found, 0, "нашли дерево у края колонны")


func test_snow_cover_in_snowy_taiga() -> void:
	var c := _find_biome(&"snowy_taiga")
	var col := gen.generate_column(c)
	var snow := Registry.block_num(&"snow_layer")
	var n := 0
	for z in 16:
		for x in 16:
			for y in range(40, 200):
				if col.get_block(x, y, z) == snow:
					n += 1
	assert_gt(n, 30, "снежный покров")
