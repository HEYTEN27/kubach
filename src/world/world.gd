class_name World
extends Node3D
## Мир: доступ к блокам, правки через действия, сохранение и floating origin.
##
## Floating origin (раздел 2.1): все мировые координаты — целые/double. Узел World стоит в
## позиции −origin, а секции — в своих абсолютных целых координатах; сумма целых в float32
## точна до 16 млн, поэтому меши не дрожат. Игрок и камера живут вне World в «сценовых»
## координатах (мир − origin), а origin переносится к игроку, когда тот отходит дальше
## REBASE_DISTANCE.

signal block_changed(pos: Vector3i, old_block: int, new_block: int)
signal origin_shifted(new_origin: Vector3i)
## Предметы выпали в мир (мировые координаты точки, стопки). Их подхватывает DroppedItems.
signal items_dropped(x: float, y: float, z: float, stacks: Array)
## Данные блока (станции) удалены — StationSystem забывает живой объект.
signal entity_removed(pos: Vector3i)

const REBASE_DISTANCE := 256.0

var registry: ContentRegistry
var generator: TerrainGenerator
var store: RegionStore
var chunks: ChunkManager
## null — временный мир без сохранения (бенчмарк, тесты).
var save: WorldSave
var world_seed := 0
var settings: WorldGenSettings
var game_mode: StringName = &"survival"
var origin := Vector3i.ZERO
## Тела, внутрь которых нельзя ставить блоки.
var bodies: Array[VoxelBody] = []
## Открытые инвентари контейнеров: Vector3i → Inventory (данные — в ChunkColumn.block_entities).
var _containers := {}
## Перед чтением данных блока (поломка) — сбросить живое состояние станции в данные:
## Callable(pos: Vector3i). Ставит StationSystem.
var entity_flush: Callable


func setup(p_registry: ContentRegistry, p_save: WorldSave, p_seed: int, p_settings: WorldGenSettings = null) -> void:
	registry = p_registry
	save = p_save
	world_seed = p_seed
	settings = p_settings if p_settings != null else WorldGenSettings.new()
	generator = TerrainGenerator.new(world_seed, registry, settings)
	store = RegionStore.new(save.region_dir() if save != null else "", registry)
	chunks = ChunkManager.new()
	chunks.name = "Chunks"
	chunks.world = self
	chunks.season = maxi(0, settings.season_index())
	RenderingServer.global_shader_parameter_set(&"world_origin", origin)
	add_child(chunks)


## Числовой ID блока или −1, если колонна не загружена. Выше мира — воздух.
func get_block(x: int, y: int, z: int) -> int:
	if y >= WorldConst.MAX_Y:
		return 0
	if y < WorldConst.MIN_Y:
		return registry.block_num(&"bedrock")
	var col: ChunkColumn = chunks.columns.get(Vector2i(x >> 4, z >> 4))
	if col == null:
		return -1
	return col.get_block(x & 15, y, z & 15)


## Индекс биома в точке (BiomeSource) или −1, если колонна не загружена.
func biome_at(x: int, z: int) -> int:
	var col: ChunkColumn = chunks.columns.get(Vector2i(x >> 4, z >> 4))
	return col.biome_at(x & 15, z & 15) if col != null else -1


func is_loaded(x: int, z: int) -> bool:
	return chunks.columns.has(Vector2i(x >> 4, z >> 4))


## Для физики: незагруженное и низ мира — твёрдые, чтобы не провалиться.
func is_solid(x: int, y: int, z: int) -> bool:
	if y < WorldConst.MIN_Y:
		return true
	var b := get_block(x, y, z)
	return b < 0 or registry.block_solid[b] == 1


func is_fluid(x: int, y: int, z: int) -> bool:
	var b := get_block(x, y, z)
	return b > 0 and registry.block_render[b] == BlockDef.RENDER_LIQUID


## Можно ли навести прицел (жидкости и воздух пропускаются).
func is_targetable(x: int, y: int, z: int) -> bool:
	var b := get_block(x, y, z)
	if b <= 0:
		return false
	if registry.block_model[b] == 1:
		return true
	return registry.block_render[b] != BlockDef.RENDER_LIQUID and registry.block_render[b] != BlockDef.RENDER_INVISIBLE


## Низкоуровневая запись блока (без проверок правил). Возвращает false, если колонна не загружена.
func set_block(x: int, y: int, z: int, block: int) -> bool:
	if y < WorldConst.MIN_Y or y >= WorldConst.MAX_Y or not WorldConst.is_inside_world_xz(x, z):
		return false
	var col: ChunkColumn = chunks.columns.get(Vector2i(x >> 4, z >> 4))
	if col == null:
		return false
	var old := col.get_block(x & 15, y, z & 15)
	if old == block:
		return true
	_remove_entity(col, x, y, z)
	col.set_block(x & 15, y, z & 15, block)
	var sec := col.sections[WorldConst.section_index(y)]
	if sec != null:
		sec.note_block(block, registry.block_opaque, registry.block_shape)
	col.dirty = true
	chunks.notify_block_changed(x, y, z)
	block_changed.emit(Vector3i(x, y, z), old, block)
	return true


## Слой действий: проверка правил и применение. true — действие выполнено.
func execute(action: GameAction) -> bool:
	var p := action.pos
	var current := get_block(p.x, p.y, p.z)
	if current < 0:
		return false
	match action.type:
		GameAction.Type.BREAK_BLOCK:
			if current == 0 or not registry.block_by_num(current).is_breakable():
				return false
			if not set_block(p.x, p.y, p.z, 0):
				return false
			if game_mode != &"creative":
				var drops := roll_drops(current)
				if not drops.is_empty():
					items_dropped.emit(p.x + 0.5, p.y + 0.3, p.z + 0.5, drops)
			_emit_bus(&"block_broken", p, current)
			return true
		GameAction.Type.PLACE_BLOCK:
			var def := registry.block_by_num(action.block)
			if def == null or action.block == 0:
				return false
			# Ставить можно в воздух, в жидкость и поверх растений и тонких слоёв (трава, снег).
			if current != 0 and registry.block_render[current] != BlockDef.RENDER_LIQUID \
					and registry.block_shape[current] == BlockDef.SHAPE_CUBE:
				return false
			if def.solid:
				for b in bodies:
					if b.intersects_block(p.x, p.y, p.z):
						return false
			if not set_block(p.x, p.y, p.z, action.block):
				return false
			if def.is_station():
				# Станция помнит поворот (к игроку) и вид — модель мешится с поворотом.
				set_entity(p, { "type": "station", "kind": String(def.station_kind), "tier": def.station_tier,
					"facing": posmod(action.facing, 4) })
				chunks.notify_block_changed(p.x, p.y, p.z)
			_emit_bus(&"block_placed", p, action.block)
			return true
	return false


## Что выпадает из блока (поле drops: шанс, min…max). Блок без drops ничего не даёт.
func roll_drops(block: int) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	var def := registry.block_by_num(block)
	if def == null:
		return out
	for d: Dictionary in def.drops:
		if randf() > float(d.get("chance", 1.0)):
			continue
		var item := registry.item(StringName(d["id"]))
		if item == null:
			continue
		var n := randi_range(int(d.get("min", 1)), int(d.get("max", 1)))
		if n > 0:
			out.append(ItemStack.create(item, n))
	return out


## Инвентарь контейнера в клетке (сундук) или null, если там не контейнер или колонна
## не загружена. Изменения сразу пишутся в данные колонны.
func get_container(x: int, y: int, z: int) -> Inventory:
	var p := Vector3i(x, y, z)
	if _containers.has(p):
		return _containers[p]
	var col: ChunkColumn = chunks.columns.get(Vector2i(x >> 4, z >> 4))
	if col == null:
		return null
	var def := registry.block_by_num(col.get_block(x & 15, y, z & 15))
	if def == null or def.container_slots <= 0:
		return null
	var key := ChunkColumn.entity_index(x & 15, y, z & 15)
	var e: Dictionary = col.block_entities.get(key, {})
	var inv := Inventory.new(registry, def.container_slots, String(def.container_kind))
	inv.from_array(e.get("items", []))
	inv.changed.connect(_on_container_changed.bind(p))
	_containers[p] = inv
	return inv


## Данные блока в клетке (станция, сундук) или пусто.
func get_entity(p: Vector3i) -> Dictionary:
	var col: ChunkColumn = chunks.columns.get(Vector2i(p.x >> 4, p.z >> 4))
	if col == null:
		return {}
	return col.block_entities.get(ChunkColumn.entity_index(p.x & 15, p.y, p.z & 15), {})


## Записать данные блока (пустой словарь — удалить).
func set_entity(p: Vector3i, e: Dictionary) -> void:
	var col: ChunkColumn = chunks.columns.get(Vector2i(p.x >> 4, p.z >> 4))
	if col == null:
		return
	var key := ChunkColumn.entity_index(p.x & 15, p.y, p.z & 15)
	if e.is_empty():
		col.block_entities.erase(key)
	else:
		col.block_entities[key] = e
	col.dirty = true


## Все стопки из данных блока: содержимое сундука, ячейки станции, входы её заданий.
static func entity_stacks(e: Dictionary) -> Array:
	var out := []
	for k: String in ["items", "in", "fuel", "out"]:
		for d: Variant in e.get(k, []):
			if d is Dictionary:
				out.append(d)
	var jobs: Array = (e.get("queue", []) as Array).duplicate()
	if not (e.get("job", {}) as Dictionary).is_empty():
		jobs.push_front(e["job"])
	for j: Dictionary in jobs:
		for d: Variant in j.get("outputs" if j.get("done", false) else "inputs", []):
			if d is Dictionary:
				out.append(d)
		if not j.get("done", false):
			var pr: Dictionary = j.get("params", {})
			if pr.get("tool") is Dictionary:
				out.append(pr["tool"])
			if pr.get("parts") is Dictionary:
				for pk: String in pr["parts"]:
					out.append(pr["parts"][pk])
	return out


## Отвязанный инвентарь (блок сломан, колонна выгружена) сюда больше не пишет.
func _on_container_changed(p: Vector3i) -> void:
	var inv: Inventory = _containers.get(p)
	var col: ChunkColumn = chunks.columns.get(Vector2i(p.x >> 4, p.z >> 4))
	if inv == null or col == null:
		return
	var key := ChunkColumn.entity_index(p.x & 15, p.y, p.z & 15)
	if inv.is_empty():
		col.block_entities.erase(key)
	else:
		col.block_entities[key] = { "type": "container", "items": inv.to_array() }
	col.dirty = true


## Блок заменён: данные блока удаляются, содержимое контейнера выпадает.
func _remove_entity(col: ChunkColumn, x: int, y: int, z: int) -> void:
	var p := Vector3i(x, y, z)
	var inv: Inventory = _containers.get(p)
	var key := ChunkColumn.entity_index(x & 15, y, z & 15)
	var items: Array = []
	if entity_flush.is_valid() and col.block_entities.has(key):
		entity_flush.call(p)
	if inv != null:
		items = inv.to_array()
		_containers.erase(p)
	elif col.block_entities.has(key):
		items = entity_stacks(col.block_entities[key])
	if not col.block_entities.has(key) and items.is_empty():
		return
	col.block_entities.erase(key)
	col.dirty = true
	entity_removed.emit(p)
	var stacks: Array[ItemStack] = []
	for d: Variant in items:
		if d is Dictionary:
			var st := ItemStack.from_dict(d)
			if st != null and registry.item(st.id) != null:
				stacks.append(st)
	if not stacks.is_empty():
		items_dropped.emit(x + 0.5, y + 0.5, z + 0.5, stacks)


## Колонна выгружена: открытые инвентари её контейнеров забываются (данные уже в колонне).
func forget_containers(cpos: Vector2i) -> void:
	for p: Vector3i in _containers.keys():
		if Vector2i(p.x >> 4, p.z >> 4) == cpos:
			_containers.erase(p)


## Сигнал в EventBus (через узел, а не идентификатор: World используется и в tools/ без автозагрузок).
func _emit_bus(sig: StringName, p: Vector3i, block: int) -> void:
	if not is_inside_tree():
		return
	var bus := get_node_or_null(^"/root/EventBus")
	if bus:
		bus.emit_signal(sig, p, block, to_scene(p.x + 0.5, p.y + 0.5, p.z + 0.5))


## Сценовые координаты точки мира.
func to_scene(wx: float, wy: float, wz: float) -> Vector3:
	return Vector3(wx - origin.x, wy - origin.y, wz - origin.z)


## Переносит origin к точке, если та ушла далеко. true — перенос был.
func update_origin(wx: float, wy: float, wz: float) -> bool:
	if absf(wx - origin.x) < REBASE_DISTANCE and absf(wy - origin.y) < REBASE_DISTANCE and absf(wz - origin.z) < REBASE_DISTANCE:
		return false
	origin = Vector3i(floori(wx / 16.0) * 16, floori(wy / 16.0) * 16, floori(wz / 16.0) * 16)
	position = -Vector3(origin)
	RenderingServer.global_shader_parameter_set(&"world_origin", origin)
	origin_shifted.emit(origin)
	return true


## Сохраняет изменённые колонны и region-файлы. Метаданные пишет Game.
func save_chunks() -> Error:
	chunks.store_dirty_columns()
	return store.flush()
