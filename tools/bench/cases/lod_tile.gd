extends RefCounted
## Плитка дальнего рельефа 64×64 блока с шагом 4 (FarTerrain._build, GDScript): высоты и биомы
## из генератора, сетка суши и воды. Идёт в WorkerThreadPool.

var name := "lod_tile_step4"
var iterations := 10
var _world: World
var _far: FarTerrain
var _i := 0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 777)
	_far = FarTerrain.new()
	_far.setup(_world, 1)


func run() -> void:
	_far._build(Vector2i(_i * 3, 5), 4)
	_far._results.clear()
	_i += 1


func teardown() -> void:
	_far.free()
	_world.free()
