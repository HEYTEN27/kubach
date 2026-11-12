extends RefCounted
## Физический кадр животных (этап 9): 40 животных бродят по равнине 4×4 колонны — решения,
## движение VoxelBody, прыжки; плюс тик жизни (вода, продукция) раз в 10 кадров.

var name := "animals_step"
var iterations := 120
var _world: World
var _sys: AnimalSystem
var _clock: GameClock
var _frame := 0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 17)
	var stone := reg.block_num(&"granite")
	var loam := reg.block_num(&"loam")
	for cz in range(-2, 2):
		for cx in range(-2, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
					col.set_block(x, 61, z, loam)
					if (x * 7 + z * 13) % 23 == 0:
						col.set_block(x, 62, z, stone)
			_world.chunks.columns[Vector2i(cx, cz)] = col
	_clock = GameClock.new(24.0)
	_sys = AnimalSystem.new()
	_sys.setup(_world, _clock)
	var ids: Array[StringName] = [&"cow", &"sheep", &"pig", &"goat", &"chicken"]
	for i in 40:
		_sys.spawn(ids[i % 5], -28.5 + (i % 8) * 7.0, 62.0, -28.5 + (i / 8) * 11.0)


func run() -> void:
	var now := _clock.total_minutes()
	for a: Animal in _sys.animals:
		_sys.step(a, 1.0 / 60.0, now)
	_frame += 1
	if _frame % 10 == 0:
		_sys.life_tick(now)


func teardown() -> void:
	_sys.free()
	_world.free()
