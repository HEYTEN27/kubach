extends RefCounted
## Пучки плотной травы на колонну (GrassField._build, 4 на блок дёрна). Идёт в WorkerThreadPool.

var name := "grass_column"
var iterations := 20
var _world: World
var _grass: GrassField
var _cols: Array = []
var _i := 0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 777)
	_grass = GrassField.new()
	_grass.chunks = _world.chunks
	_grass.setup(_world.chunks, BlockTextures.load_default(reg, false))
	for n in 4:
		_cols.append(_world.generator.generate_column(Vector2i(n * 5, 3)))


func run() -> void:
	var col: ChunkColumn = _cols[_i % _cols.size()]
	_grass._build(col.cpos, col, 1, 4)
	_grass._results.clear()
	_i += 1


func teardown() -> void:
	_grass.free()
	_world.free()
