extends RefCounted
## Шаг клеточного автомата воды (главный поток, 5 раз в секунду): прорыв плотины —
## бассейн 12×12×4 конечной воды на возвышении растекается по равнине 5×5 колонн.

var name := "fluid_step"
var iterations := 30
var _world: World
var _sim: FluidSim


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_world = World.new()
	_world.setup(reg, null, 13)
	var stone := reg.block_num(&"granite")
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
			_world.chunks.columns[Vector2i(cx, cz)] = col
	var full := reg.fluid_level_blocks[reg.fluid_ids.find(&"water")][8]
	_sim = FluidSim.new(_world, reg)
	for y in range(64, 68):
		for z in 12:
			for x in 12:
				_world.set_block(x, y, z, full)
				_sim.wake(Vector3i(x, y, z))
	for z in 12:
		for x in 12:
			for y in range(61, 64):
				_world.set_block(x, y, z, stone)


var _calc := 0.0
var _apply := 0.0
var _changes := 0


func run() -> void:
	_sim.step()
	_calc += _sim.stat_calc_ms
	_apply += _sim.stat_apply_ms
	_changes += _sim.stat_changes


func teardown() -> void:
	print("  fluid_step: расчёт %.2f мс, применение %.2f мс, изменений %.0f за шаг" % [_calc / iterations,
		_apply / iterations, float(_changes) / iterations])
	_world.free()
