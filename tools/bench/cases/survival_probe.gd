extends RefCounted
## Опрос окружения для выживания (главный поток, раз в 0,25 с): температура, тепло блоков
## в радиусе 7, контакт, вода — и 15 тиков PlayerVitals (кадры между опросами при 60 FPS).

var name := "survival_probe"
var iterations := 20
var _world: World
var _probe: EnvironmentProbe
var _clock: GameClock
var _vitals: PlayerVitals


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 7)
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			var stone := reg.block_num(&"granite")
			for z in 16:
				for x in 16:
					for y in range(56, 64):
						col.set_block(x, y, z, stone)
			_world.chunks.columns[Vector2i(cx, cz)] = col
	_world.set_block(3, 64, 3, reg.block_num(&"campfire"))
	_clock = GameClock.new()
	_vitals = PlayerVitals.from_registry(reg)
	_probe = EnvironmentProbe.new(_world, _vitals.cfg)


func run() -> void:
	var env := _probe.sample(0.5, 64.0, 0.5, 65.6, _clock)
	for i in 15:
		_vitals.tick(0.016, 0.016 / 60.0, env)


func teardown() -> void:
	_world.free()
