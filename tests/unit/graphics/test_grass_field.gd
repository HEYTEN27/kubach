extends GutTest
## Плотная трава: пучки только на верхнем дёрне, под листвой — меньше света неба.

var world: World
var grass: GrassField


func before_all() -> void:
	world = World.new()
	world.setup(Registry, null, 99)
	add_child(world)
	grass = GrassField.new()
	world.add_child(grass)
	grass.setup(world.chunks, BlockTextures.load_default(Registry, false))


func after_all() -> void:
	world.chunks.wait_all()
	grass.wait_all()
	world.queue_free()


func _column() -> ChunkColumn:
	var col := ChunkColumn.new(Vector2i(0, 0))
	var turf := Registry.block_num(&"turf")
	var stone := Registry.block_num(&"granite")
	var leaves := Registry.block_num(&"oak_leaves")
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, turf)
	col.set_block(3, 61, 3, stone)          # камень на дёрне — травы нет
	col.set_block(5, 70, 5, leaves)         # крона над дёрном
	col.set_block(7, 61, 7, Registry.block_num(&"grass"))  # растение не мешает
	return col


func test_surface_rules() -> void:
	var col := _column()
	assert_eq(grass._surface(col, 0, 0)[0], 60)
	assert_eq(grass._surface(col, 3, 3), [], "сверху камень")
	assert_eq(grass._surface(col, 5, 5)[2], 0.55, "под кроной темнее")
	assert_eq(grass._surface(col, 7, 7)[0], 60, "сквозь растение")


func test_build_instances() -> void:
	var col := _column()
	grass._build(Vector2i(0, 0), col, 1, 3)
	var r: Array = grass._results.pop_back()
	assert_eq(r[2], 255 * 3, "255 столбов дёрна × 3 пучка")
	assert_eq((r[1] as PackedFloat32Array).size(), r[2] * 20)
