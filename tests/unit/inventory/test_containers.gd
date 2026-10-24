extends GutTest
## Контейнеры: инвентарь сундука в мире, сохранение в region-файле, выпадение при поломке.

var world: World
var chest: int
var dropped: Array = []


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 5)
	world.game_mode = &"survival"
	var col := ChunkColumn.new(Vector2i(0, 0))
	var stone := Registry.block_num(&"granite")
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, stone)
	world.chunks.columns[Vector2i(0, 0)] = col
	chest = Registry.block_num(&"chest_wood")
	dropped.clear()
	world.items_dropped.connect(func(_x: float, _y: float, _z: float, stacks: Array) -> void: dropped.append_array(stacks))


func after_each() -> void:
	world.free()


func test_chest_block_is_container() -> void:
	assert_eq(Registry.block(&"chest_wood").container_slots, 27)
	assert_eq(Registry.block(&"chest_iron").container_slots, 54)
	assert_null(world.get_container(1, 60, 1), "камень — не контейнер")


func test_container_contents_live_in_column() -> void:
	assert_true(world.set_block(2, 61, 3, chest))
	var inv := world.get_container(2, 61, 3)
	assert_not_null(inv)
	assert_eq(inv.size(), 27)
	inv.add(ItemStack.create(Registry.item(&"stick"), 10))
	var col: ChunkColumn = world.chunks.columns[Vector2i(0, 0)]
	var key := ChunkColumn.entity_index(2, 61, 3)
	assert_true(col.block_entities.has(key))
	assert_true(col.dirty)
	assert_eq(world.get_container(2, 61, 3), inv, "тот же инвентарь при повторном открытии")


func test_breaking_chest_drops_contents() -> void:
	world.set_block(2, 61, 3, chest)
	world.get_container(2, 61, 3).add(ItemStack.create(Registry.item(&"flint"), 7))
	assert_true(world.execute(GameAction.break_block(Vector3i(2, 61, 3))))
	var ids := {}
	for s: ItemStack in dropped:
		ids[s.id] = ids.get(s.id, 0) + s.count
	assert_eq(ids.get(&"flint", 0), 7, "содержимое выпало")
	assert_eq(ids.get(&"chest_wood", 0), 1, "и сам сундук")
	var col: ChunkColumn = world.chunks.columns[Vector2i(0, 0)]
	assert_true(col.block_entities.is_empty())


func test_creative_break_drops_no_block() -> void:
	world.game_mode = &"creative"
	world.set_block(4, 61, 4, Registry.block_num(&"granite"))
	world.execute(GameAction.break_block(Vector3i(4, 61, 4)))
	assert_eq(dropped.size(), 0)


func test_drop_chances() -> void:
	var leaves := Registry.block_num(&"oak_leaves")
	var sticks := 0
	for i in 400:
		for s: ItemStack in world.roll_drops(leaves):
			sticks += s.count
	assert_between(sticks, 20, 80, "палки из листвы примерно в 12% случаев")


func test_region_roundtrip_with_entities() -> void:
	world.set_block(2, 61, 3, chest)
	world.get_container(2, 61, 3).add(ItemStack.create(Registry.item(&"stick"), 10))
	var col: ChunkColumn = world.chunks.columns[Vector2i(0, 0)]
	var store := RegionStore.new("", Registry)
	var blob := store.encode_column(col)
	var back := store.decode_column(blob, Vector2i(0, 0))
	assert_eq(back.block_entities.size(), 1)
	var items: Array = back.block_entities[ChunkColumn.entity_index(2, 61, 3)]["items"]
	assert_eq(items[0]["id"], "stick")
	assert_eq(int(items[0]["n"]), 10)


func test_reads_format_1_columns() -> void:
	var col: ChunkColumn = world.chunks.columns[Vector2i(0, 0)]
	var store := RegionStore.new("", Registry)
	var blob := store.encode_column(col)
	# Формат 1: без хвоста данных блоков.
	var raw := blob.slice(4).decompress(blob.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
	raw.encode_u16(4, 1)
	raw = raw.slice(0, raw.size() - 2)
	var old := PackedByteArray()
	old.resize(4)
	old.encode_u32(0, raw.size())
	old.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	var back := store.decode_column(old, Vector2i(0, 0))
	assert_not_null(back, "старые сохранения открываются")
	assert_eq(back.get_block(5, 60, 5), Registry.block_num(&"granite"))
