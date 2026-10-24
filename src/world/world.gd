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
	return b > 0 and registry.block_render[b] != BlockDef.RENDER_LIQUID and registry.block_render[b] != BlockDef.RENDER_INVISIBLE


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
			_emit_bus(&"block_placed", p, action.block)
			return true
	return false


## Сигнал в EventBus (через узел, а не идентификатор: World используется и в tools/ без автозагрузок).
func _emit_bus(sig: StringName, p: Vector3i, block: int) -> void:
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
