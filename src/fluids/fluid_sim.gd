class_name FluidSim
extends RefCounted
## Жидкости (раздел 10 ТЗ, этап 8): клеточный автомат с уровнями 1…8 на блок и конечным
## объёмом. Природные источники (океан, реки, озёра — блок-источник из data/fluids.json)
## бесконечны: отдают воду, не убывая. Конечная вода (ведро, стёкшая) сохраняет объём.
##
## Шаг (step) обходит только «бодрствующие» клетки — изменённые на прошлом шаге и их соседей.
## Правила для клетки с жидкостью:
## 1. Реакции: соседняя чужая жидкость застывает (лава + вода = обсидиан/базальт), огонь гаснет.
## 2. Вниз: стекает в клетку ниже, сколько туда влезет (водопады, заполнение ям).
## 3. Вбок: если вниз некуда — делится с соседом, у которого уровень ниже хотя бы на
##    min_spread (меньшая разница — лужа застывает, вода не растекается бесконечно тонким слоем).
## 4. Давление (сообщающиеся сосуды): если клетка локально успокоилась, в связном теле
##    жидкости до PRESSURE_CAP клеток вода
##    переходит с самой высокой открытой поверхности в самое низкое свободное место, пока разница
##    поверхностей не меньше min_spread уровней. Так уровни в сосудах, соединённых снизу, выравниваются.
## Изменённые клетки будят соседей; клетки, где ничего не произошло, засыпают. Клетки в
## колоннах дальше radius от центра (и у края загруженного мира) откладываются в «сон по
## колоннам» и просыпаются, когда игрок рядом / колонна загрузилась.
## Мир — любой объект с get_block/set_block (World или помощник тестов).
##
## Для World шаг считает нативный NativeFluid (native/kubach_native, тот же алгоритм на C++:
## читает секции колонн напрямую, свои записи отдаёт списком изменений) — GDScript-версия
## остаётся эталоном (test_native_fluid сравнивает мир после шагов). KUBACH_NO_NATIVE=1 — GDScript.

const DIRS_SIDE: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const DIRS_ALL: Array[Vector3i] = [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1), Vector3i(0, 1, 0)]
const PRESSURE_CAP := 1024
## Клеток за шаг не больше — остальные ждут следующего шага.
const MAX_CELLS := 800

var world: Object
var reg: ContentRegistry
## Клетки, которые проверяются на этом шаге (Vector3i → true).
var active := {}
## Спящие по колоннам: Vector2i → { Vector3i → true }.
var sleeping := {}
## Центр (колонна игрока) и радиус симуляции в колоннах; radius < 0 — без ограничения (тесты).
var center := Vector2i.ZERO
var radius := -1
var steps := 0
## Последний шаг: обработано клеток, изменено клеток.
var stat_cells := 0
var stat_changes := 0
## Время последнего шага: расчёт (C++) и применение изменений к миру, мс.
var stat_calc_ms := 0.0
var stat_apply_ms := 0.0
## Счётчик застываний (лава + вода) — для звука и пара; позиции — для частиц.
var reactions: Array[Vector3i] = []

var _fire := 0
var _replace := PackedByteArray()   # блок → 1: жидкость его смывает (растения, снег, огонь)
var _min_spread := PackedInt32Array()
var _extinguish := PackedByteArray()
var _react := {}                    # Vector2i(f, g) → [source_to, flowing_to]
var _next := {}
## NativeFluid или null (GDScript).
var native: Object


func _init(p_world: Object, p_reg: ContentRegistry, use_native: bool = true) -> void:
	world = p_world
	reg = p_reg
	_fire = maxi(0, reg.block_num(&"fire"))
	_replace.resize(reg.block_count())
	for b in range(1, reg.block_count()):
		var def := reg.block_by_num(b)
		if def == null or def.solid or reg.block_fluid[b] != 0 or def.has_model() or def.container_kind != &"":
			continue
		if reg.block_shape[b] != BlockDef.SHAPE_CUBE or b == _fire:
			_replace[b] = 1
	for i in reg.fluid_ids.size():
		var e := reg.get_entry("fluids", reg.fluid_ids[i])
		_min_spread.append(int(e.get("min_spread", 2)))
		_extinguish.append(1 if e.get("extinguishes", false) else 0)
		for r: Dictionary in e.get("reactions", []):
			var g := reg.fluid_ids.find(StringName(r["with"]))
			if g >= 0:
				_react[Vector2i(i + 1, g + 1)] = [reg.block_num(StringName(r["source_to"])),
					reg.block_num(StringName(r["flowing_to"]))]
	if use_native and world is World and ClassDB.class_exists(&"NativeFluid") and not OS.has_environment("KUBACH_NO_NATIVE"):
		native = ClassDB.instantiate(&"NativeFluid")
		var lv := []
		for a in reg.fluid_level_blocks:
			lv.append(a)
		native.call(&"setup", reg.block_fluid, reg.block_fluid_level, reg.block_fluid_source, reg.block_solid, _replace,
			_fire, reg.block_num(&"bedrock"), lv, _min_spread, _extinguish, _react, WorldConst.MIN_Y, WorldConst.MAX_Y)


## Уровень клетки для вида f: 0 — пусто (воздух или смываемое), 1…8 — уровень этой жидкости,
## −1 — занято (твёрдое, чужая жидкость, не загружено). Источник — 8.
func level_at(f: int, b: int) -> int:
	if b == 0:
		return 0
	if b < 0:
		return -1
	if reg.block_fluid[b] == f:
		return reg.block_fluid_level[b]
	if _replace[b] == 1:
		return 0
	return -1


func is_source(b: int) -> bool:
	return b > 0 and reg.block_fluid_source[b] == 1


## Проснуться клетке и соседям (после правки блока).
func wake(p: Vector3i) -> void:
	if native != null:
		native.wake(p.x, p.y, p.z)
		return
	_add(active, p)
	for d in DIRS_ALL:
		_add(active, p + d)


func _activate(p: Vector3i) -> void:
	if native != null:
		native.add_active(p.x, p.y, p.z)
	else:
		active[p] = true


## Колонна загрузилась: будим её спящие клетки и конечную воду в ней (вдруг она текла).
func wake_column(cpos: Vector2i, col: ChunkColumn) -> void:
	var s: Dictionary = sleeping.get(cpos, {})
	sleeping.erase(cpos)
	for p: Vector3i in s:
		_activate(p)
	if col == null:
		return
	for si in col.sections.size():
		var sec: ChunkSection = col.sections[si]
		if sec == null or sec.is_uniform():
			continue
		var blocks := sec.blocks
		var any := false
		for f in reg.fluid_level_blocks.size():
			var lv := reg.fluid_level_blocks[f]
			for k in range(1, 9):
				if lv[k] > 0 and blocks.has(lv[k]):
					any = true
					break
			if any:
				break
		if not any:
			continue
		for i in blocks.size():
			var b := blocks[i]
			if b > 0 and reg.block_fluid[b] != 0 and reg.block_fluid_source[b] == 0:
				_activate(Vector3i(cpos.x * 16 + (i & 15), WorldConst.MIN_Y + si * 16 + (i >> 8), cpos.y * 16 + ((i >> 4) & 15)))


## Центр симуляции сменился: просыпаются спящие колонны в радиусе.
func set_center(c: Vector2i) -> void:
	if c == center:
		return
	center = c
	for cpos: Vector2i in sleeping.keys():
		if _in_radius(cpos):
			for p: Vector3i in sleeping[cpos]:
				_activate(p)
			sleeping.erase(cpos)


func active_count() -> int:
	return native.active_count() if native != null else active.size()


func sleeping_count() -> int:
	var n := 0
	for c: Vector2i in sleeping:
		n += (sleeping[c] as Dictionary).size()
	return n


## Один шаг автомата. Возвращает число изменённых клеток.
func step() -> int:
	steps += 1
	reactions.clear()
	if native != null:
		return _step_native()
	_next = {}
	var changes := 0
	var cells := 0
	var bodies := {}   # уже проверенные давлением клетки
	for p: Vector3i in active.keys():
		if cells >= MAX_CELLS:
			break
		active.erase(p)
		var cpos := Vector2i(p.x >> 4, p.z >> 4)
		if not _in_radius(cpos):
			_sleep(cpos, p)
			continue
		cells += 1
		changes += _cell(p, bodies)
	# Необработанное — на следующий шаг.
	for p: Vector3i in active:
		_next[p] = true
	active = _next
	stat_cells = cells
	stat_changes = changes
	return changes


func _step_native() -> int:
	var t0 := Time.get_ticks_usec()
	var res: Dictionary = native.step((world as World).chunks.columns, steps, center, radius, MAX_CELLS)
	var t1 := Time.get_ticks_usec()
	(world as World).apply_changes(res["changes"])
	stat_calc_ms = (t1 - t0) / 1000.0
	stat_apply_ms = (Time.get_ticks_usec() - t1) / 1000.0
	var sl: PackedInt32Array = res["sleep"]
	for i in range(0, sl.size(), 5):
		_sleep(Vector2i(sl[i], sl[i + 1]), Vector3i(sl[i + 2], sl[i + 3], sl[i + 4]))
	var rc: PackedInt32Array = res["reactions"]
	for i in range(0, rc.size(), 3):
		reactions.append(Vector3i(rc[i], rc[i + 1], rc[i + 2]))
	stat_cells = res["cells"]
	stat_changes = res["changes_count"]
	return stat_changes


## Активные клетки по порядку (для сравнения с нативной версией).
func active_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if native != null:
		var a: PackedInt32Array = native.active_list()
		for i in range(0, a.size(), 3):
			out.append(Vector3i(a[i], a[i + 1], a[i + 2]))
	else:
		for p: Vector3i in active:
			out.append(p)
	return out


func _cell(p: Vector3i, bodies: Dictionary) -> int:
	var b: int = world.get_block(p.x, p.y, p.z)
	if b <= 0:
		return 0
	var f := reg.block_fluid[b]
	if f == 0:
		return 0
	var changes := _reactions(p, f)
	var lvl := reg.block_fluid_level[b]
	var src := reg.block_fluid_source[b] == 1
	var levels := reg.fluid_level_blocks[f - 1]
	if levels[8] <= 0:
		return changes   # не течёт (лава)
	# Вниз.
	var below := p + Vector3i.DOWN
	var bb: int = world.get_block(below.x, below.y, below.z)
	if bb < 0:
		_sleep(Vector2i(below.x >> 4, below.z >> 4), p)
		return changes
	var bl := level_at(f, bb)
	if bl >= 0 and bl < 8 and not is_source(bb):
		var amount := mini(lvl, 8 - bl)
		_put(below, f, bl + amount)
		changes += 1
		if not src:
			lvl -= amount
			_put(p, f, lvl)
			changes += 1
		if lvl == 0:
			return changes
		if bl + amount < 8:
			return changes   # всё ушло вниз, вбок нечего
	# Вбок: к соседям с уровнем ниже хотя бы на min_spread; через край обрыва (под соседом
	# пусто) — при любой разнице, вода не задерживается на краю.
	var ms := _min_spread[f - 1]
	var start := steps % 4
	for i in 4:
		var q: Vector3i = p + DIRS_SIDE[(start + i) % 4]
		var nb: int = world.get_block(q.x, q.y, q.z)
		if nb < 0:
			_sleep(Vector2i(q.x >> 4, q.z >> 4), p)
			continue
		if lvl <= 0:
			continue
		var nl := level_at(f, nb)
		if nl < 0 or is_source(nb):
			continue
		var diff := lvl - nl
		var need := ms
		if nl == 0:
			var under := level_at(f, world.get_block(q.x, q.y - 1, q.z))
			if under >= 0 and under < 8:
				need = 1
		if diff < need:
			continue
		var t := maxi(1, diff / 2)
		_put(q, f, nl + t)
		changes += 1
		if not src:
			lvl -= t
			_put(p, f, lvl)
			changes += 1
	# Давление — только для клеток, которые локально успокоились (иначе вода и так течёт).
	if lvl > 0 and not src and changes == 0 and not bodies.has(p):
		changes += _pressure(p, f, bodies)
	return changes


## Лава + вода, огонь. Возвращает число изменений.
func _reactions(p: Vector3i, f: int) -> int:
	var n := 0
	for d in DIRS_ALL:
		var q := p + d
		var nb: int = world.get_block(q.x, q.y, q.z)
		if nb <= 0:
			continue
		if nb == _fire and _extinguish[f - 1] == 1:
			world.set_block(q.x, q.y, q.z, 0)
			_wake_next(q)
			n += 1
			continue
		var g := reg.block_fluid[nb]
		if g == 0 or g == f:
			continue
		var r: Variant = _react.get(Vector2i(f, g))
		if r == null:
			continue
		var to: int = r[0] if is_source(nb) else r[1]
		if to > 0:
			world.set_block(q.x, q.y, q.z, to)
			reactions.append(q)
			_wake_next(q)
			n += 1
	return n


## Сообщающиеся сосуды: в связном теле жидкости вида f (до PRESSURE_CAP клеток) переносим
## единицы с самой высокой открытой поверхности в самое низкое место, куда вода может войти.
func _pressure(start: Vector3i, f: int, bodies: Dictionary) -> int:
	var seen := { start: true }
	var queue: Array[Vector3i] = [start]
	var donor := Vector3i.ZERO
	var donor_s := -(1 << 40)
	var donor_src := false
	var recv := Vector3i.ZERO
	var recv_s := 1 << 40
	var qi := 0
	while qi < queue.size():
		var c: Vector3i = queue[qi]
		qi += 1
		if queue.size() > PRESSURE_CAP:
			for x: Vector3i in queue:
				bodies[x] = true
			return 0
		var b: int = world.get_block(c.x, c.y, c.z)
		var l := reg.block_fluid_level[b]
		var up: int = world.get_block(c.x, c.y + 1, c.z)
		var s := c.y * 8 + l
		# Открытая поверхность — над клеткой не эта жидкость.
		if (up <= 0 or reg.block_fluid[up] != f) and s > donor_s:
			donor_s = s
			donor = c
			donor_src = is_source(b)
		if l < 8 and not is_source(b) and s < recv_s and _supported(c, f):
			recv_s = s
			recv = c
		for d in DIRS_ALL:
			var q := c + d
			if seen.has(q):
				continue
			var nb: int = world.get_block(q.x, q.y, q.z)
			if nb > 0 and reg.block_fluid[nb] == f:
				seen[q] = true
				queue.append(q)
			elif level_at(f, nb) == 0:
				# Пустая клетка рядом с телом: сюда вода может войти (если под ней опора).
				seen[q] = true
				var qs := q.y * 8
				if qs < recv_s and _supported(q, f):
					recv_s = qs
					recv = q
	for x: Vector3i in queue:
		bodies[x] = true
	if donor_s - recv_s < _min_spread[f - 1] or donor == recv:
		return 0
	var dl := reg.block_fluid_level[world.get_block(donor.x, donor.y, donor.z)]
	var rb: int = world.get_block(recv.x, recv.y, recv.z)
	var rl := maxi(0, level_at(f, rb))
	var t := mini((donor_s - recv_s) / 2, 8 - rl)
	if not donor_src:
		t = mini(t, dl)
	if t <= 0:
		return 0
	_put(recv, f, rl + t)
	if not donor_src:
		_put(donor, f, dl - t)
	return 2


## Под клеткой опора: твёрдое или полная жидкость (иначе вода не стоит, а падает).
func _supported(c: Vector3i, f: int) -> bool:
	var b: int = world.get_block(c.x, c.y - 1, c.z)
	if b < 0:
		return false
	if b == 0:
		return false
	if reg.block_fluid[b] == f:
		return reg.block_fluid_level[b] == 8
	return reg.block_solid[b] == 1 or _replace[b] == 0


## Записать уровень (0 — воздух) и разбудить окрестность на следующий шаг.
func _put(p: Vector3i, f: int, level: int) -> void:
	var cur: int = world.get_block(p.x, p.y, p.z)
	if is_source(cur):
		return
	var b := 0 if level <= 0 else reg.fluid_level_blocks[f - 1][mini(level, 8)]
	world.set_block(p.x, p.y, p.z, b)
	_wake_next(p)


func _wake_next(p: Vector3i) -> void:
	_next[p] = true
	for d in DIRS_ALL:
		_next[p + d] = true


func _add(set: Dictionary, p: Vector3i) -> void:
	set[p] = true


func _sleep(cpos: Vector2i, p: Vector3i) -> void:
	if not sleeping.has(cpos):
		sleeping[cpos] = {}
	(sleeping[cpos] as Dictionary)[p] = true


func _in_radius(cpos: Vector2i) -> bool:
	if radius < 0:
		return true
	return absi(cpos.x - center.x) <= radius and absi(cpos.y - center.y) <= radius


## Объём конечной жидкости вида f в прямоугольнике (для тестов и отладки).
func volume(f: int, from: Vector3i, to: Vector3i) -> int:
	var v := 0
	for y in range(from.y, to.y + 1):
		for z in range(from.z, to.z + 1):
			for x in range(from.x, to.x + 1):
				var b: int = world.get_block(x, y, z)
				if b > 0 and reg.block_fluid[b] == f and reg.block_fluid_source[b] == 0:
					v += reg.block_fluid_level[b]
	return v


## Течение в клетке (блоков/с, мировые оси): к соседям с поверхностью ниже, вниз — если под
## клеткой пусто. Для источников течения нет (реки — FluidSystem через генератор).
func flow_at(p: Vector3i) -> Vector3:
	var b: int = world.get_block(p.x, p.y, p.z)
	if b <= 0 or reg.block_fluid[b] == 0 or is_source(b):
		return Vector3.ZERO
	var f := reg.block_fluid[b]
	var lvl := reg.block_fluid_level[b]
	var out := Vector3.ZERO
	var below: int = world.get_block(p.x, p.y - 1, p.z)
	var bl := level_at(f, below)
	if bl >= 0 and bl < 8 and not is_source(below):
		out.y = -1.0
	for d in DIRS_SIDE:
		var nb: int = world.get_block(p.x + d.x, p.y, p.z + d.z)
		var nl := level_at(f, nb)
		if nl < 0:
			continue
		if nl == 0:
			var under := level_at(f, world.get_block(p.x + d.x, p.y - 1, p.z + d.z))
			if under >= 0 and under < 8:
				nl = -2   # обрыв: вода стекает туда сильнее
		if nl < lvl:
			out += Vector3(d) * float(lvl - nl) / 8.0
	return out
