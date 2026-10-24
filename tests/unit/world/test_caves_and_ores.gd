extends GutTest
## Пещеры и руды (разделы 2.3, 2.5).

var gen: TerrainGenerator


func before_all() -> void:
	gen = TerrainGenerator.new(777, Registry)


func _count(col: ChunkColumn, pred: Callable, y_from: int = -256, y_to: int = 319) -> int:
	var n := 0
	for y in range(y_from, y_to + 1):
		for z in 16:
			for x in 16:
				if pred.call(col.get_block(x, y, z), y):
					n += 1
	return n


func test_caves_exist_underground() -> void:
	var air := 0
	for i in 8:
		var col := gen.generate_column(Vector2i(i * 11, i * 3))
		air += _count(col, func(b: int, _y: int) -> bool: return b == 0, -240, 0)
	assert_gt(air, 500, "под землёй есть пустоты")


func test_no_caves_when_disabled() -> void:
	var st := WorldGenSettings.new()
	st.caves = 0.0
	st.ores = 0.0
	var g := TerrainGenerator.new(777, Registry, st)
	for i in 4:
		var col := g.generate_column(Vector2i(i * 11, i * 3))
		var holes := _count(col, func(b: int, _y: int) -> bool: return b == 0, -240, 0)
		assert_eq(holes, 0, "пещеры 0 — пустот нет")


func test_lava_only_deep() -> void:
	var lava := Registry.block_num(&"lava")
	for i in 8:
		var col := gen.generate_column(Vector2i(i * 13 - 40, i * 7))
		var high := _count(col, func(b: int, y: int) -> bool: return b == lava and y > -160)
		assert_eq(high, 0, "лава только ниже −160")


func test_bedrock_intact() -> void:
	var bedrock := Registry.block_num(&"bedrock")
	for i in 4:
		var col := gen.generate_column(Vector2i(i * 9, -i * 9))
		var holes := _count(col, func(b: int, _y: int) -> bool: return b != bedrock, -256, -250)
		assert_eq(holes, 0)


func test_ocean_floor_not_breached() -> void:
	# Под водой пещеры не подходят к дну ближе 8 блоков: море не проваливается.
	var checked := 0
	for i in 40:
		var cx := i * 23 - 300
		var cz := -i * 17 + 120
		var info := gen.surface_info(cx * 16 + 8, cz * 16 + 8)
		if info[1] == TerrainGenerator.NO_WATER or info[0] >= info[1] - 2:
			continue
		var col := gen.generate_column(Vector2i(cx, cz))
		for y in range(info[0] - 7, info[0] + 1):
			assert_ne(col.get_block(8, y, 8), 0, "дно на y=%d цело" % y)
		checked += 1
	assert_gt(checked, 3, "проверено морских колонн: %d" % checked)


func test_ores_present_and_absent_when_disabled() -> void:
	var ore_blocks := {}
	for e in Registry.get_entries("blocks"):
		if "ore" in e["tags"] or "gem" in e["tags"]:
			ore_blocks[Registry.block_num(e["id"])] = true
	var n := 0
	for i in 10:
		n += _count(gen.generate_column(Vector2i(i * 5, i * 2)), func(b: int, _y: int) -> bool: return ore_blocks.has(b), -250, 80)
	assert_gt(n, 50, "руды встречаются")
	var st := WorldGenSettings.new()
	st.ores = 0.0
	var g := TerrainGenerator.new(777, Registry, st)
	var none := _count(g.generate_column(Vector2i(5, 2)), func(b: int, _y: int) -> bool: return ore_blocks.has(b), -250, 80)
	assert_eq(none, 0, "руды 0 — руд нет")


func test_diamonds_only_in_kimberlite_deep() -> void:
	# Ищем трубку перебором колонн (они редкие); алмазы — только ниже −180 и рядом с кимберлитом.
	var diamond := Registry.block_num(&"diamond_ore")
	var kimb := Registry.block_num(&"kimberlite")
	var pipes := 0
	for i in 400:
		var col := gen.generate_column(Vector2i(i * 31 % 900 - 450, i * 17 % 700 - 350))
		var k := _count(col, func(b: int, _y: int) -> bool: return b == kimb, -250, -40)
		if k == 0:
			continue
		pipes += 1
		for y in range(-250, -39):
			for z in 16:
				for x in 16:
					if col.get_block(x, y, z) == diamond:
						assert_lte(y, -180, "алмаз на y=%d" % y)
		if pipes >= 2:
			break
	assert_gt(pipes, 0, "нашли кимберлитовую трубку")


func test_ores_respect_depth() -> void:
	var platinum := Registry.block_num(&"platinum_ore")
	var ruby := Registry.block_num(&"ruby_ore")
	for i in 12:
		var col := gen.generate_column(Vector2i(i * 3, -i * 4))
		var bad := _count(col, func(b: int, y: int) -> bool: return (b == platinum and y > -150) or (b == ruby and y > -130))
		assert_eq(bad, 0, "ценное — глубоко")
