class_name ChunkManager
extends Node3D
## Загрузка, генерация, мешинг и выгрузка колонн вокруг игрока.
##
## Генерация (или чтение из region-файла) и greedy-мешинг идут в WorkerThreadPool.
## Главный поток только раздаёт задачи, принимает результаты и создаёт меши — не дольше
## apply_budget_usec за кадр (раздел 20 ТЗ).
##
## Порядок для колонны: генерация → свет (когда загружены все 8 соседей: свет считается по
## области 3×3, см. VoxelLight) → мешинг секций. Свет секции — постоянный цвет или 3D-текстура
## 18³ в материале секции. Правка блока пересчитывает свет 3×3 колонн и меняет только материалы.

## Колонна загружена (сгенерирована или прочитана) — станции в ней оживают.
signal column_loaded(cpos: Vector2i)
## Колонна сейчас выгрузится — успеть записать живое состояние станций в её данные.
signal column_unloading(cpos: Vector2i)

## Радиус загрузки в колоннах (настройка «дальность прорисовки»).
var view_distance := 12
## Колонны выгружаются на расстоянии view_distance + unload_margin (чтобы не дёргать на границе).
var unload_margin := 2
## Отсечение пещер: «глубокие» секции (целиком ниже поверхности колонны на DEEP_MARGIN) мешатся
## только в этом радиусе колонн от игрока — издалека их всё равно не видно.
var underground_radius := 4
const DEEP_MARGIN := 8
var apply_budget_usec := 3000
var max_gen_in_flight := maxi(2, OS.get_processor_count() - 1)
## Мешинг секции в C++ — доли миллисекунды: задач в полёте должно хватать, чтобы потоки не
## простаивали между кадрами (результаты забираются раз в кадр).
var max_mesh_in_flight := maxi(4, OS.get_processor_count() * 4)
var max_light_in_flight := maxi(2, OS.get_processor_count())

var world: World
## Vector2i -> ChunkColumn.
var columns := {}

# Статистика для F3.
var stat_quads := 0
var stat_last_apply_ms := 0.0
var stat_meshes_applied := 0

## GreedyMesher (GDScript) или NativeMesher (C++) — см. GreedyMesher.create_best().
var _mesher: Object
## Модели станций (этап 6) — дописываются к мешу секции.
var _models: ModelMesher
## NativeLight (C++) или VoxelLight. Без нативной библиотеки свет выключен (GDScript-расчёт
## занимает секунды на колонну): все секции — полный свет неба.
var _light: Object
var lighting_enabled := true
## Материалы поверхностей и текстуры блоков (этап 3).
var materials: BlockMaterials
## Сезон для цветов травы и листвы (0 — весна … 3 — зима). Смена сезона — этап 7.
var season := 1
var _center := Vector2i(1 << 30, 0)
var _wanted: Array[Vector2i] = []
var _wanted_cursor := 0
var _meshed := {}          # Vector2i -> true: секции колонны уже поставлены в мешинг
var _deep_meshed := {}     # Vector2i -> true: глубокие секции колонны тоже в работе
var _gen_tasks := {}       # Vector2i -> id задачи
var _mesh_tasks := {}      # Vector3i(cx, si, cz) -> id задачи
var _mesh_queue: Array[Vector3i] = []
var _mesh_queued := {}     # Vector3i -> true
var _mesh_again := {}      # секция изменилась, пока её мешили
var _priority := {}        # Vector3i -> true: правки игрока, применяются вне очереди
var _nodes := {}           # Vector3i -> MeshInstance3D
var _section_quads := {}   # Vector3i -> int
var _results_mutex := Mutex.new()
var _gen_results: Array = []   # [cpos, ChunkColumn]
var _mesh_results: Array = []  # [key, Dictionary] — от потоков, под мьютексом
var _to_apply: Array = []      # готовые результаты, ждущие бюджета главного потока
var _lit := {}             # Vector2i -> true: свет колонны применён (можно мешить)
var _light_tasks := {}     # Vector2i -> id задачи
var _light_queue: Array[Vector2i] = []
var _light_queued := {}
var _light_again := {}     # колонну поменяли, пока считался свет
var _light_results: Array = []   # [cpos, Array] — от потоков, под мьютексом
var _light_to_apply: Array = []
var _section_light := {}   # Vector3i -> Color или ImageTexture3D
var _light_mats := {}      # Vector3i -> { поверхность: ShaderMaterial } для секций с текстурой света
var _node_surfs := {}      # Vector3i -> Array[StringName]: поверхности меша по порядку


func _ready() -> void:
	_mesher = GreedyMesher.create_best(world.registry)
	_models = ModelMesher.new(world.registry)
	_light = VoxelLight.create_best(world.registry)
	if not VoxelLight.is_native(_light):
		lighting_enabled = false
		push_warning("ChunkManager: нет нативной библиотеки — воксельный свет выключен")
	if materials == null:
		materials = BlockMaterials.new(BlockTextures.load_default(world.registry))


func _exit_tree() -> void:
	wait_all()


## Сменить дальность прорисовки на ходу (настройки графики).
func set_view_distance(v: int) -> void:
	if v == view_distance:
		return
	view_distance = v
	_center = Vector2i(1 << 30, 0)


## Вызывается каждый кадр с колонной, где стоит игрок.
func update(center: Vector2i) -> void:
	_collect_gen_results()
	if center != _center:
		_center = center
		_rebuild_wanted()
		_unload_far()
		_update_underground()
	_dispatch_gen()
	_dispatch_light()
	_dispatch_mesh()
	_apply_mesh_results()


## Ждёт все задачи потоков (выход из игры, тесты).
func wait_all() -> void:
	for id: int in _gen_tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_gen_tasks.clear()
	for id: int in _mesh_tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_mesh_tasks.clear()
	for id: int in _light_tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_light_tasks.clear()
	_results_mutex.lock()
	_gen_results.clear()
	_mesh_results.clear()
	_light_results.clear()
	_results_mutex.unlock()
	_to_apply.clear()
	_light_to_apply.clear()
	_priority.clear()


## Загружены ли колонны в радиусе и готовы ли их меши (для экрана загрузки).
func is_area_ready(center: Vector2i, radius: int) -> bool:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dz)
			if not columns.has(c) or not _meshed.has(c) or not _lit.has(c):
				return false
	for key: Vector3i in _mesh_queued:
		if absi(key.x - center.x) <= radius and absi(key.z - center.y) <= radius:
			return false
	for key: Vector3i in _mesh_tasks:
		if absi(key.x - center.x) <= radius and absi(key.z - center.y) <= radius:
			return false
	for item: Array in _to_apply:
		var key: Vector3i = item[0]
		if absi(key.x - center.x) <= radius and absi(key.z - center.y) <= radius:
			return false
	return true


## Колонны в генерации и ещё не розданные в пределах дальности.
func pending_generation() -> int:
	var queued := 0
	for i in range(_wanted_cursor, _wanted.size()):
		if not columns.has(_wanted[i]):
			queued += 1
	return _gen_tasks.size() + queued


func pending_meshing() -> int:
	_results_mutex.lock()
	var waiting := _mesh_results.size()
	_results_mutex.unlock()
	return _mesh_tasks.size() + _mesh_queue.size() + _to_apply.size() + waiting + pending_lighting()


func pending_lighting() -> int:
	_results_mutex.lock()
	var waiting := _light_results.size()
	_results_mutex.unlock()
	return _light_tasks.size() + _light_queue.size() + _light_to_apply.size() + waiting


func light_name() -> String:
	if not lighting_enabled:
		return "выкл."
	return "C++" if VoxelLight.is_native(_light) else "GDScript"


## Свет в мировой клетке (для F3): [небо, R, G, B] уровни 0…15 или [] — нет данных.
func light_at(x: int, y: int, z: int) -> Array:
	var si := WorldConst.section_index(y)
	if si < 0:
		return []
	var key := Vector3i(x >> 4, si, z >> 4)
	if not _section_light.has(key):
		return []
	var l: Variant = _section_light[key]
	if l is Color:
		return [roundi(l.r * 15), roundi(l.g * 15), roundi(l.b * 15), roundi(l.a * 15)]
	var tex: ImageTexture3D = l
	var img: Image = tex.get_data()[(y & 15) + 1]
	var c := img.get_pixel((x & 15) + 1, (z & 15) + 1)
	return [roundi(c.r * 15), roundi(c.g * 15), roundi(c.b * 15), roundi(c.a * 15)]


func mesher_name() -> String:
	return "C++" if GreedyMesher.is_native(_mesher) else "GDScript"


## Колонна освещена и её секции поставлены в мешинг.
func is_column_meshed(c: Vector2i) -> bool:
	return _meshed.has(c)


func mesh_node_count() -> int:
	return _nodes.size()


## Перемешать секцию с блоком и соседние, если блок на краю секции.
func notify_block_changed(x: int, y: int, z: int) -> void:
	var cpos := Vector2i(x >> 4, z >> 4)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := cpos + Vector2i(dx, dz)
			if _lit.has(c):
				_queue_light(c, true)
	var si := WorldConst.section_index(y)
	_queue_mesh(Vector3i(cpos.x, si, cpos.y), true)
	var lx := x & 15
	var ly := y & 15
	var lz := z & 15
	if lx == 0:
		_queue_mesh(Vector3i(cpos.x - 1, si, cpos.y), true)
	elif lx == 15:
		_queue_mesh(Vector3i(cpos.x + 1, si, cpos.y), true)
	if lz == 0:
		_queue_mesh(Vector3i(cpos.x, si, cpos.y - 1), true)
	elif lz == 15:
		_queue_mesh(Vector3i(cpos.x, si, cpos.y + 1), true)
	if ly == 0 and si > 0:
		_queue_mesh(Vector3i(cpos.x, si - 1, cpos.y), true)
	elif ly == 15 and si < WorldConst.SECTIONS_PER_COLUMN - 1:
		_queue_mesh(Vector3i(cpos.x, si + 1, cpos.y), true)


## Отдаёт изменённые загруженные колонны в RegionStore (перед flush).
func store_dirty_columns() -> int:
	var n := 0
	for col: ChunkColumn in columns.values():
		if col.dirty:
			world.store.store_column(col)
			col.dirty = false
			n += 1
	return n


func _in_radius(c: Vector2i, center: Vector2i, radius: int) -> bool:
	var d := c - center
	return d.x * d.x + d.y * d.y <= radius * radius + radius


func _rebuild_wanted() -> void:
	_wanted.clear()
	var r := view_distance
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := _center + Vector2i(dx, dz)
			if _in_radius(c, _center, r):
				_wanted.append(c)
	var center := _center
	_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())
	_wanted_cursor = 0


func _dispatch_gen() -> void:
	while _gen_tasks.size() < max_gen_in_flight and _wanted_cursor < _wanted.size():
		var c := _wanted[_wanted_cursor]
		_wanted_cursor += 1
		if columns.has(c) or _gen_tasks.has(c):
			continue
		# Генерация — критический путь загрузки (GDScript почти не ускоряется от потоков):
		# высокий приоритет, чтобы не ждать за светом и мешингом.
		_gen_tasks[c] = WorkerThreadPool.add_task(_gen_task.bind(c), true, "gen %s" % c)


func _gen_task(cpos: Vector2i) -> void:
	var col := world.store.load_column(cpos)
	if col == null:
		col = world.generator.generate_column(cpos)
	else:
		# Биомы и цвета не сохраняются — их даёт сид.
		world.generator.fill_climate(col)
	_results_mutex.lock()
	_gen_results.append([cpos, col])
	_results_mutex.unlock()


func _collect_gen_results() -> void:
	_results_mutex.lock()
	var results := _gen_results
	_gen_results = []
	_results_mutex.unlock()
	for r: Array in results:
		var cpos: Vector2i = r[0]
		WorkerThreadPool.wait_for_task_completion(_gen_tasks[cpos])
		_gen_tasks.erase(cpos)
		if not _in_radius(cpos, _center, view_distance + unload_margin):
			continue
		columns[cpos] = r[1]
		_on_column_added(cpos)


func _on_column_added(cpos: Vector2i) -> void:
	column_loaded.emit(cpos)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := cpos + Vector2i(dx, dz)
			if _lit.has(c) or _light_queued.has(c) or _light_tasks.has(c) or not columns.has(c):
				continue
			if _neighbors_loaded(c):
				_queue_light(c, false)


func _neighbors_loaded(c: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not columns.has(c + Vector2i(dx, dz)):
				return false
	return true


## Свет колонны готов в первый раз: ставим её секции в мешинг.
func _on_column_lit(c: Vector2i) -> void:
	if _meshed.has(c):
		return
	_meshed[c] = true
	var col: ChunkColumn = columns[c]
	var deep := _in_radius(c, _center, underground_radius)
	if deep:
		_deep_meshed[c] = true
	for si in WorldConst.SECTIONS_PER_COLUMN:
		if col.sections[si] != null and (deep or not _is_deep(col, si)):
			_queue_mesh(Vector3i(c.x, si, c.y), false)


func _queue_light(c: Vector2i, priority: bool) -> void:
	if _light_tasks.has(c):
		_light_again[c] = true
		return
	if _light_queued.has(c):
		if priority:
			_light_queue.erase(c)
			_light_queue.push_front(c)
		return
	_light_queued[c] = true
	if priority:
		_light_queue.push_front(c)
	else:
		_light_queue.push_back(c)


func _dispatch_light() -> void:
	while _light_tasks.size() < max_light_in_flight and not _light_queue.is_empty():
		var c: Vector2i = _light_queue.pop_front()
		_light_queued.erase(c)
		if not columns.has(c) or not _neighbors_loaded(c):
			continue
		if not lighting_enabled:
			_light_to_apply.append([c, []])
			continue
		var area := []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var col: ChunkColumn = columns[c + Vector2i(dx, dz)]
				var snaps := []
				snaps.resize(WorldConst.SECTIONS_PER_COLUMN)
				for si in WorldConst.SECTIONS_PER_COLUMN:
					if col.sections[si] != null:
						snaps[si] = GreedyMesher.snapshot(col.sections[si])
				area.append(snaps)
		_light_tasks[c] = WorkerThreadPool.add_task(_light_task.bind(c, area), false, "light %s" % c)


func _light_task(c: Vector2i, area: Array) -> void:
	var res: Array = _light.light_column(area)
	_results_mutex.lock()
	_light_results.append([c, res])
	_results_mutex.unlock()


func _collect_light_results() -> void:
	_results_mutex.lock()
	var fresh := _light_results
	_light_results = []
	_results_mutex.unlock()
	for item: Array in fresh:
		var c: Vector2i = item[0]
		WorkerThreadPool.wait_for_task_completion(_light_tasks[c])
		_light_tasks.erase(c)
		if _light_again.has(c):
			_light_again.erase(c)
			_queue_light(c, true)
		_light_to_apply.append(item)


## Применяет свет колонны: данные секций, материалы готовых мешей, первый мешинг.
func _apply_light(c: Vector2i, res: Array) -> void:
	if not columns.has(c):
		return
	for si in WorldConst.SECTIONS_PER_COLUMN:
		var key := Vector3i(c.x, si, c.y)
		var l: Variant = res[si] if not res.is_empty() else VoxelLight.SKY_FULL
		var old: Variant = _section_light.get(key)
		if l is Color:
			if old is Color and old == l:
				continue
			_section_light[key] = l
			_light_mats.erase(key)
		else:
			var tex: ImageTexture3D = old if old is ImageTexture3D else null
			if tex != null:
				tex.update(VoxelLight.make_images(l))
			else:
				_section_light[key] = VoxelLight.make_texture(l)
				_light_mats.erase(key)
		_refresh_materials(key)
	if not _lit.has(c):
		_lit[c] = true
		_on_column_lit(c)


func _material(key: Vector3i, surf: StringName) -> ShaderMaterial:
	var l: Variant = _section_light.get(key, VoxelLight.SKY_FULL)
	if l is Color:
		return materials.for_const(surf, l)
	var mats: Dictionary = _light_mats.get(key, {})
	if not mats.has(surf):
		mats[surf] = materials.for_light(surf, l)
		_light_mats[key] = mats
	return mats[surf]


func _refresh_materials(key: Vector3i) -> void:
	var node: MeshInstance3D = _nodes.get(key)
	if node == null:
		return
	var surfs: Array = _node_surfs.get(key, [])
	for i in surfs.size():
		node.mesh.surface_set_material(i, _material(key, surfs[i]))


## Секция целиком ниже поверхности колонны.
func _is_deep(col: ChunkColumn, si: int) -> bool:
	return WorldConst.section_base_y(si) + 15 < col.surface_min - DEEP_MARGIN


## Глубокие секции: мешим у колонн, вошедших в радиус, и убираем у вышедших из него.
func _update_underground() -> void:
	for c: Vector2i in _deep_meshed.keys():
		if _in_radius(c, _center, underground_radius + 1) and columns.has(c):
			continue
		_deep_meshed.erase(c)
		var col: ChunkColumn = columns.get(c)
		if col == null:
			continue
		for si in WorldConst.SECTIONS_PER_COLUMN:
			if _is_deep(col, si):
				_remove_node(Vector3i(c.x, si, c.y))
	var r := underground_radius
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := _center + Vector2i(dx, dz)
			if _deep_meshed.has(c) or not _meshed.has(c) or not _in_radius(c, _center, r):
				continue
			_deep_meshed[c] = true
			var col: ChunkColumn = columns[c]
			for si in WorldConst.SECTIONS_PER_COLUMN:
				if col.sections[si] != null and _is_deep(col, si):
					_queue_mesh(Vector3i(c.x, si, c.y), false)


func _unload_far() -> void:
	var limit := view_distance + unload_margin
	for cpos: Vector2i in columns.keys():
		if _in_radius(cpos, _center, limit):
			continue
		var col: ChunkColumn = columns[cpos]
		column_unloading.emit(cpos)
		if col.dirty:
			world.store.store_column(col)
		for si in WorldConst.SECTIONS_PER_COLUMN:
			_remove_node(Vector3i(cpos.x, si, cpos.y))
		world.forget_containers(cpos)
		columns.erase(cpos)
		_meshed.erase(cpos)
		_deep_meshed.erase(cpos)
		_lit.erase(cpos)
		if _light_queued.has(cpos):
			_light_queued.erase(cpos)
			_light_queue.erase(cpos)
		for si in WorldConst.SECTIONS_PER_COLUMN:
			var key := Vector3i(cpos.x, si, cpos.y)
			_section_light.erase(key)
			_light_mats.erase(key)


func _queue_mesh(key: Vector3i, priority: bool) -> void:
	var cpos := Vector2i(key.x, key.z)
	if not _meshed.has(cpos):
		return
	if not _deep_meshed.has(cpos) and _is_deep(columns[cpos], key.y):
		return
	if priority:
		_priority[key] = true
	if _mesh_queued.has(key):
		if priority:
			_mesh_queue.erase(key)
			_mesh_queue.push_front(key)
		return
	_mesh_queued[key] = true
	if priority:
		_mesh_queue.push_front(key)
	else:
		_mesh_queue.push_back(key)


func _dispatch_mesh() -> void:
	while _mesh_tasks.size() < max_mesh_in_flight and not _mesh_queue.is_empty():
		var key: Vector3i = _mesh_queue.pop_front()
		_mesh_queued.erase(key)
		var cpos := Vector2i(key.x, key.z)
		if not columns.has(cpos):
			continue
		if _mesh_tasks.has(key):
			_mesh_again[key] = true
			continue
		var si := key.y
		var col: ChunkColumn = columns[cpos]
		if _is_buried(cpos, si):
			# Однородный непрозрачный камень со всех сторон: граней нет, поток не нужен.
			_apply_mesh(key, { "quads": 0 })
			continue
		var center := GreedyMesher.snapshot(col.sections[si])
		var nbs := [
			_snap(cpos + Vector2i.LEFT, si), _snap(cpos + Vector2i.RIGHT, si),
			_snap(cpos, si - 1), _snap(cpos, si + 1),
			_snap(cpos + Vector2i.UP, si), _snap(cpos + Vector2i.DOWN, si),
		]
		var origin := Vector3i(cpos.x * 16, WorldConst.section_base_y(si), cpos.y * 16)
		var facings := _section_facings(col, si) if _models.any_in(center) else {}
		_mesh_tasks[key] = WorkerThreadPool.add_task(_mesh_task.bind(key, center, nbs, col.tints, origin, facings), false, "mesh %s" % key)


## Повороты моделей станций секции: локальный индекс → 0…3 (из данных блоков колонны).
static func _section_facings(col: ChunkColumn, si: int) -> Dictionary:
	var out := {}
	for k: int in col.block_entities:
		var e: Dictionary = col.block_entities[k]
		if not e.has("facing"):
			continue
		var p := ChunkColumn.entity_pos(k)
		if WorldConst.section_index(p.y) == si:
			out[WorldConst.local_index(p.x, p.y & 15, p.z)] = int(e["facing"])
	return out


## Секция и все шесть соседей — однородные непрозрачные блоки (низ мира считается непрозрачным).
## Секция и все шесть соседей целиком из непрозрачных кубов (низ мира считается закрытым).
func _is_buried(cpos: Vector2i, si: int) -> bool:
	if not _all_opaque(cpos, si):
		return false
	for c: Vector2i in [cpos + Vector2i.LEFT, cpos + Vector2i.RIGHT, cpos + Vector2i.UP, cpos + Vector2i.DOWN]:
		if not _all_opaque(c, si):
			return false
	return (si == 0 or _all_opaque(cpos, si - 1)) and _all_opaque(cpos, si + 1)


func _all_opaque(cpos: Vector2i, si: int) -> bool:
	if si < 0 or si >= WorldConst.SECTIONS_PER_COLUMN:
		return false
	var col: ChunkColumn = columns.get(cpos)
	if col == null:
		return false
	var s := col.sections[si]
	return s != null and s.all_opaque


func _snap(cpos: Vector2i, si: int) -> Variant:
	if si < 0 or si >= WorldConst.SECTIONS_PER_COLUMN:
		return null
	var col: ChunkColumn = columns.get(cpos)
	if col == null or col.sections[si] == null:
		return null
	return GreedyMesher.snapshot(col.sections[si])


func _mesh_task(key: Vector3i, center: Array, nbs: Array, tints: PackedColorArray, origin: Vector3i,
		facings: Dictionary = {}) -> void:
	var res: Dictionary = _mesher.mesh_section(center, nbs, tints, season, origin)
	if _models.any_in(center):
		var arr := _models.build(center, facings)
		if not arr.is_empty():
			res["models"] = arr
			res["quads"] = int(res["quads"]) + (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 6
	_results_mutex.lock()
	_mesh_results.append([key, res])
	_results_mutex.unlock()


func _apply_mesh_results() -> void:
	# Сначала забираем все готовые результаты: поток освобождается сразу, а не когда
	# меш дойдёт до главного потока.
	_results_mutex.lock()
	var fresh := _mesh_results
	_mesh_results = []
	_results_mutex.unlock()
	for item: Array in fresh:
		var key: Vector3i = item[0]
		WorkerThreadPool.wait_for_task_completion(_mesh_tasks[key])
		_mesh_tasks.erase(key)
		if _mesh_again.has(key):
			# Секцию поменяли, пока её мешили: этот результат устарел, считаем заново.
			_mesh_again.erase(key)
			_queue_mesh(key, true)
		if _priority.has(key) and not _mesh_queued.has(key):
			_priority.erase(key)
			_to_apply.push_front(item)
		else:
			_to_apply.append(item)

	_collect_light_results()
	var t0 := Time.get_ticks_usec()
	while not _light_to_apply.is_empty() and Time.get_ticks_usec() - t0 < apply_budget_usec:
		var li: Array = _light_to_apply.pop_front()
		_apply_light(li[0], li[1])
	var applied := 0
	while not _to_apply.is_empty() and Time.get_ticks_usec() - t0 < apply_budget_usec:
		var item: Array = _to_apply.pop_front()
		var key: Vector3i = item[0]
		var cp := Vector2i(key.x, key.z)
		if columns.has(cp) and (_deep_meshed.has(cp) or not _is_deep(columns[cp], key.y)):
			_apply_mesh(key, item[1])
			applied += 1
	if applied > 0:
		stat_last_apply_ms = (Time.get_ticks_usec() - t0) / 1000.0
		stat_meshes_applied += applied


func _apply_mesh(key: Vector3i, res: Dictionary) -> void:
	stat_quads += int(res["quads"]) - int(_section_quads.get(key, 0))
	_section_quads[key] = res["quads"]
	if res["quads"] == 0:
		_remove_node(key)
		return
	var mesh := ArrayMesh.new()
	var surfs: Array[StringName] = []
	for surf: StringName in BlockMaterials.SURFACES:
		var arrays: Array = res.get(surf, [])
		if arrays.is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key, surf))
		surfs.append(surf)
	var models: Array = res.get("models", [])
	if not models.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, models)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(key, &"opaque"))
		surfs.append(&"opaque")
	_node_surfs[key] = surfs
	var node: MeshInstance3D = _nodes.get(key)
	if node == null:
		node = MeshInstance3D.new()
		node.position = Vector3(key.x * 16, WorldConst.section_base_y(key.y), key.z * 16)
		_nodes[key] = node
		add_child(node)
	node.mesh = mesh


func _remove_node(key: Vector3i) -> void:
	var node: MeshInstance3D = _nodes.get(key)
	if node != null:
		node.queue_free()
		_nodes.erase(key)
		_node_surfs.erase(key)
	stat_quads -= int(_section_quads.get(key, 0))
	_section_quads.erase(key)
