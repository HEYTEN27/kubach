extends GutTest
## Клеточный автомат жидкостей: ведро в яму, водопад, сообщающиеся сосуды, источники,
## лава + вода, огонь, сон по колоннам, течение.

var stone: int
var water: int
var lava: int
var wf: int


func before_all() -> void:
	stone = Registry.block_num(&"granite")
	water = Registry.block_num(&"water")
	lava = Registry.block_num(&"lava")
	wf = Registry.fluid_ids.find(&"water") + 1


func _level(n: int) -> int:
	return Registry.fluid_level_blocks[wf - 1][n]


func _run(sim: FluidSim, max_steps: int = 400) -> int:
	for i in max_steps:
		if sim.step() == 0 and sim.active_count() == 0:
			return i
	return max_steps


## Ведро (8 уровней) в яму 3×3 глубиной 1: уровень выравнивается, объём сохраняется.
func test_bucket_into_pit_levels_out() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 2
	w.fill(Vector3i(0, 1, 0), Vector3i(2, 1, 2), 0)   # яма на y = 1
	var sim := FluidSim.new(w, Registry)
	w.set_block(1, 1, 1, _level(8))
	sim.wake(Vector3i(1, 1, 1))
	var steps := _run(sim)
	assert_lt(steps, 400, "вода успокоилась")
	assert_eq(sim.volume(wf, Vector3i(-1, 0, -1), Vector3i(3, 3, 3)), 8, "объём сохранился")
	var lo := 99
	var hi := -1
	for z in 3:
		for x in 3:
			var b := w.get_block(x, 1, z)
			var l: int = Registry.block_fluid_level[b] if b > 0 else 0
			lo = mini(lo, l)
			hi = maxi(hi, l)
	assert_lte(hi - lo, 1, "уровень выровнялся (разница не больше 1/8)")
	for x in range(-1, 4):
		assert_eq(w.get_block(x, 2, -1), 0, "через край ямы не вылилось")


## Вода с уступа стекает вниз водопадом и собирается внизу.
func test_waterfall_reaches_ground() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 0
	w.fill(Vector3i(0, 0, 0), Vector3i(0, 5, 0), stone)   # столб-уступ
	var sim := FluidSim.new(w, Registry)
	w.set_block(0, 6, 0, _level(8))
	sim.wake(Vector3i(0, 6, 0))
	_run(sim)
	assert_eq(sim.volume(wf, Vector3i(-4, 0, -4), Vector3i(4, 8, 4)), 8, "объём сохранился")
	assert_eq(w.get_block(0, 6, 0), 0, "наверху ничего не осталось")
	var bottom := sim.volume(wf, Vector3i(-4, 0, -4), Vector3i(4, 0, 4))
	assert_eq(bottom, 8, "вся вода на земле")


## U-образная трубка: вода в одном колене поднимается в другом до того же уровня.
func test_communicating_vessels() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 12
	# Колена (x = 0 и x = 4) с y 1…11, внизу тоннель y = 1 от x = 0 до 4.
	w.fill(Vector3i(0, 1, 0), Vector3i(0, 11, 0), 0)
	w.fill(Vector3i(4, 1, 0), Vector3i(4, 11, 0), 0)
	w.fill(Vector3i(1, 1, 0), Vector3i(3, 1, 0), 0)
	var sim := FluidSim.new(w, Registry)
	# Левое колено полно до y = 9 (конечная вода).
	for y in range(1, 10):
		w.set_block(0, y, 0, _level(8))
		sim.wake(Vector3i(0, y, 0))
	var vol := sim.volume(wf, Vector3i(0, 0, 0), Vector3i(4, 12, 0))
	_run(sim, 2000)
	assert_eq(sim.volume(wf, Vector3i(0, 0, 0), Vector3i(4, 12, 0)), vol, "объём сохранился")
	var left := _surface(w, 0)
	var right := _surface(w, 4)
	assert_lte(absi(left - right), 1, "поверхности в коленах сравнялись: %d и %d (в 1/8 блока)" % [left, right])
	assert_gt(right, 3 * 8, "вода поднялась в правом колене")


func _surface(w: GridWorld, x: int) -> int:
	var top := 0
	for y in range(1, 12):
		var b := w.get_block(x, y, 0)
		if b > 0 and Registry.block_fluid[b] != 0:
			top = y * 8 + Registry.block_fluid_level[b]
	return top


## Природный источник бесконечен: заполняет яму и не убывает.
func test_source_fills_pit_and_stays() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 3
	w.fill(Vector3i(0, 1, 0), Vector3i(3, 2, 3), 0)
	w.set_block(0, 2, 0, water)
	var sim := FluidSim.new(w, Registry)
	sim.wake(Vector3i(0, 2, 0))
	_run(sim, 1000)
	assert_eq(w.get_block(0, 2, 0), water, "источник на месте")
	for z in 4:
		for x in 4:
			var b := w.get_block(x, 1, z)
			assert_true(b > 0 and Registry.block_fluid_level[b] == 8, "нижний ряд ямы полон (%d, %d)" % [x, z])


## Лава + вода: источник лавы — обсидиан; огонь гаснет.
func test_lava_and_fire() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 1
	w.set_block(1, 1, 0, lava)
	var fire := Registry.block_num(&"fire")
	w.set_block(-1, 1, 0, fire)
	var sim := FluidSim.new(w, Registry)
	w.set_block(0, 1, 0, _level(8))
	sim.wake(Vector3i(0, 1, 0))
	sim.step()
	assert_eq(w.get_block(1, 1, 0), Registry.block_num(&"obsidian"), "лава застыла обсидианом")
	assert_ne(w.get_block(-1, 1, 0), fire, "огонь погас")
	assert_eq(sim.reactions.size(), 1, "пар/шипение один раз")


## Клетки вне радиуса засыпают и просыпаются, когда игрок рядом; у края загруженного — тоже.
func test_sleep_and_wake() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 1
	w.hi = Vector2i(200, 200)
	var sim := FluidSim.new(w, Registry)
	sim.radius = 2
	w.set_block(100, 1, 100, _level(8))
	sim.wake(Vector3i(100, 1, 100))
	sim.step()
	assert_eq(w.get_block(100, 1, 100), _level(8), "далеко — не течёт")
	assert_gt(sim.sleeping_count(), 0, "клетки уснули")
	sim.set_center(Vector2i(6, 6))
	_run(sim)
	assert_eq(sim.volume(wf, Vector3i(90, 1, 90), Vector3i(110, 1, 110)), 8)
	assert_ne(w.get_block(100, 1, 100), _level(8), "проснулась и растеклась")
	# Край загруженного: вода у границы ждёт загрузки колонны.
	var e := GridWorld.new(stone)
	e.floor_y = 1
	e.hi = Vector2i(15, 15)
	var s2 := FluidSim.new(e, Registry)
	e.set_block(15, 1, 5, _level(8))
	s2.wake(Vector3i(15, 1, 5))
	_run(s2)
	assert_true(s2.sleeping.has(Vector2i(1, 0)), "ждёт соседнюю колонну")


## Течение: к низкому соседу и к обрыву; у источника течения нет.
func test_flow_direction() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 1
	w.set_block(0, 1, 0, _level(6))
	w.set_block(1, 1, 0, _level(2))
	for q: Vector3i in [Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1)]:
		w.set_block(q.x, q.y, q.z, stone)
	var sim := FluidSim.new(w, Registry)
	var f := sim.flow_at(Vector3i(0, 1, 0))
	assert_gt(f.x, 0.0, "течёт к соседу с уровнем ниже")
	w.set_block(0, 1, 0, water)
	assert_eq(sim.flow_at(Vector3i(0, 1, 0)), Vector3.ZERO)


## Растекание по ровному: лужа не становится тоньше 1/8 и не уходит бесконечно.
func test_puddle_is_finite() -> void:
	var w := GridWorld.new(stone)
	w.floor_y = 1
	var sim := FluidSim.new(w, Registry)
	w.set_block(0, 1, 0, _level(8))
	sim.wake(Vector3i(0, 1, 0))
	_run(sim)
	assert_eq(sim.volume(wf, Vector3i(-20, 1, -20), Vector3i(20, 1, 20)), 8)
	var cells := 0
	for p: Vector3i in w.cells:
		if w.cells[p] > 0 and Registry.block_fluid[w.cells[p]] != 0:
			cells += 1
	assert_lte(cells, 8, "8 единиц — не больше 8 клеток")
