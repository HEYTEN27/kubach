extends RefCounted
## Кадр фермы (этап 9): досчёт FRAME_BUDGET культур (бюджет FarmSystem на кадр) из поля 400 грядок —
## условия (крыша, вода, температура, сорняки), рост, смена стадий.

var name := "farm_tick"
var iterations := 30
var _world: World
var _farm: FarmSystem
var _clock: GameClock


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 19)
	var stone := reg.block_num(&"granite")
	var land := reg.block_num(&"farmland")
	var water := reg.block_num(&"water")
	for cz in range(-2, 2):
		for cx in range(-2, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
					col.set_block(x, 61, z, water if x % 5 == 0 else land)
			_world.chunks.columns[Vector2i(cx, cz)] = col
	_clock = GameClock.new(24.0)
	_farm = FarmSystem.new()
	_farm.setup(_world, _clock, PlayerVitals.from_registry(reg, &"normal").cfg)
	var crops: Array[StringName] = [&"wheat", &"carrot", &"potato", &"cabbage", &"tomato"]
	var n := 0
	for z in range(-20, 20):
		for x in range(-25, 25):
			if posmod(x, 5) == 0 or n >= 400:
				continue
			_farm.plant(Vector3i(x, 62, z), crops[n % 5])
			n += 1


func run() -> void:
	_clock.advance_hours(1.0)
	var now := _clock.total_minutes()
	var i := 0
	for p: Vector3i in _farm.crops.keys():
		_farm.update_crop(p, now)
		i += 1
		if i >= FarmSystem.FRAME_BUDGET:
			break


func teardown() -> void:
	_farm.free()
	_world.free()
