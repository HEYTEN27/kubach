extends RefCounted
## Тик погоды в главном потоке: шаг WeatherSim, SurfaceTicker (снегопад в радиусе 56 блоков),
## FireSystem с 60 огнями в лесу, выбор точки молнии. Мир — 9×9 плоских колонн.

var name := "weather_tick"
var iterations := 30
var _world: World
var _sim: WeatherSim
var _ticker: SurfaceTicker
var _fire: FireSystem
var _rng := RandomNumberGenerator.new()
var _climate := { "weather": ["snow", "blizzard"], "season": "winter", "temp": -8.0 }
var _temp := func(_x: int, _y: int, _z: int) -> float: return -8.0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 11)
	var stone := reg.block_num(&"granite")
	var leaves := reg.block_num(&"oak_leaves")
	for cz in range(-4, 5):
		for cx in range(-4, 5):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
					if cx == 1 and cz == 1:
						col.set_block(x, 61, z, leaves)
			_world.chunks.columns[Vector2i(cx, cz)] = col
	_sim = WeatherSim.new(reg, 5)
	_sim.force(&"blizzard")
	_ticker = SurfaceTicker.new(_world)
	_fire = FireSystem.new(_world)
	_rng.seed = 9
	for i in 60:
		_fire.ignite(Vector3i(16 + (i % 16), 61, 16 + (i / 16) * 3))


func run() -> void:
	_sim.advance(0.05, _climate)
	var w := _sim.values(-8.0)
	_ticker.tick(0.0, 0.0, w, _temp, 0.05)
	_fire.tick(1.0, Callable())
	LightningTarget.pick(_world, 0, 0, _rng, 60)


func teardown() -> void:
	_world.free()
