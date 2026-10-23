class_name ContentRegistry
extends Node
## Реестр контента (автозагрузка `Registry`). Загружает всё из data/ и отдаёт системам.
##
## Раскладка data/:
##   data/<категория>.json        — базовые записи категории;
##   data/<категория>/*.json      — дополнения (загружаются после базового файла, по алфавиту);
##   data/schemas/<категория>.json — схема категории. Категория без схемы загружается
##                                   «как есть» с предупреждением.
## Каждый файл: { "format": 1, "entries": [ { "id": "...", ... }, ... ] }.
##
## Блоки дополнительно получают числовые ID (0 — всегда воздух) и плоские массивы свойств
## для горячих циклов мешинга и освещения.

const DEFAULT_DATA_DIR := "res://data"
const SCHEMA_DIR := "schemas"
const SUPPORTED_FORMAT := 1
const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const AIR := &"air"
## Блоки в чанках хранятся как uint16.
const MAX_BLOCKS := 65536

## Ошибки последней загрузки. Пустой массив — данные корректны.
var errors: PackedStringArray = []
var warnings: PackedStringArray = []
var loaded := false
var data_dir := DEFAULT_DATA_DIR

## Плоские массивы по числовому ID блока (индекс = BlockDef.num).
var block_solid := PackedByteArray()
var block_opaque := PackedByteArray()
var block_light_emission := PackedByteArray()
var block_light_filter := PackedByteArray()
## Код BlockDef.RENDER_*.
var block_render := PackedByteArray()
var block_color := PackedColorArray()

var _schemas := {}   # категория -> схема (Dictionary)
var _entries := {}   # категория -> { StringName id -> Dictionary }
var _order := {}     # категория -> Array[StringName], порядок загрузки
var _sources := {}   # "категория:id" -> путь файла (для сообщений о дублях)
var _blocks: Array[BlockDef] = []
var _block_nums := {}  # StringName -> int
var _id_regex := RegEx.create_from_string(ID_PATTERN)


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	load_all()
	for e in errors:
		push_error("Registry: " + e)
	for w in warnings:
		push_warning("Registry: " + w)
	print("Registry: %d категорий, %d блоков, ошибок %d, %.1f мс" % [
		_entries.size(), _blocks.size(), errors.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	# Не через идентификатор EventBus: реестр используется и в tools/ без автозагрузок.
	var bus := get_node_or_null(^"/root/EventBus")
	if bus:
		bus.registry_loaded.emit(errors.size())


## Полностью перезагружает реестр из каталога. Возвращает true, если ошибок нет.
func load_all(dir: String = DEFAULT_DATA_DIR) -> bool:
	_clear()
	data_dir = dir
	if not DirAccess.dir_exists_absolute(dir):
		errors.append("каталог данных не найден: %s" % dir)
		return false

	var validator := SchemaValidator.new()
	_load_schemas(dir.path_join(SCHEMA_DIR), validator)
	for category in _discover_categories(dir):
		for path in _category_files(dir, category):
			_load_file(path, category, validator)
	_resolve_refs(validator)
	errors.append_array(validator.errors)
	_build_blocks()
	loaded = errors.is_empty()
	return loaded


func categories() -> PackedStringArray:
	var out := PackedStringArray(_entries.keys())
	out.sort()
	return out


func has_entry(category: String, id: StringName) -> bool:
	return _entries.has(category) and _entries[category].has(id)


## Нормализованная запись (с подставленными значениями по умолчанию) или пустой словарь.
func get_entry(category: String, id: StringName) -> Dictionary:
	if not has_entry(category, id):
		return {}
	return _entries[category][id]


## Все записи категории в порядке загрузки.
func get_entries(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _entries.has(category):
		return out
	for id: StringName in _order[category]:
		out.append(_entries[category][id])
	return out


func block_count() -> int:
	return _blocks.size()


## Числовой ID блока или -1, если такого нет.
func block_num(id: StringName) -> int:
	return _block_nums.get(id, -1)


func block(id: StringName) -> BlockDef:
	var n: int = _block_nums.get(id, -1)
	return _blocks[n] if n >= 0 else null


func block_by_num(n: int) -> BlockDef:
	return _blocks[n] if n >= 0 and n < _blocks.size() else null


func _clear() -> void:
	errors = PackedStringArray()
	warnings = PackedStringArray()
	loaded = false
	_schemas.clear()
	_entries.clear()
	_order.clear()
	_sources.clear()
	_blocks.clear()
	_block_nums.clear()
	block_solid = PackedByteArray()
	block_opaque = PackedByteArray()
	block_light_emission = PackedByteArray()
	block_light_filter = PackedByteArray()
	block_render = PackedByteArray()
	block_color = PackedColorArray()


func _load_schemas(dir: String, validator: SchemaValidator) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in _sorted_json_files(dir):
		var path := dir.path_join(file)
		var root: Variant = _parse_json(path)
		if root == null:
			continue
		if typeof(root) != TYPE_DICTIONARY:
			errors.append("%s: схема должна быть объектом" % path)
			continue
		var category: String = root.get("category", file.get_basename())
		if category != file.get_basename():
			errors.append("%s: category '%s' не совпадает с именем файла" % [path, category])
			continue
		if validator.check_fields_spec(root.get("fields"), path):
			if not root["fields"].has("id"):
				errors.append("%s: в схеме нет поля 'id'" % path)
				continue
			_schemas[category] = root


func _discover_categories(dir: String) -> PackedStringArray:
	var found := {}
	for file in _sorted_json_files(dir):
		found[file.get_basename()] = true
	for sub in DirAccess.get_directories_at(dir):
		if sub != SCHEMA_DIR and not sub.begins_with("."):
			found[sub] = true
	var out := PackedStringArray(found.keys())
	out.sort()
	return out


func _category_files(dir: String, category: String) -> PackedStringArray:
	var out := PackedStringArray()
	var base := dir.path_join(category + ".json")
	if FileAccess.file_exists(base):
		out.append(base)
	var sub := dir.path_join(category)
	if DirAccess.dir_exists_absolute(sub):
		for file in _sorted_json_files(sub):
			out.append(sub.path_join(file))
	return out


func _load_file(path: String, category: String, validator: SchemaValidator) -> void:
	var root: Variant = _parse_json(path)
	if root == null:
		return
	if typeof(root) != TYPE_DICTIONARY or typeof(root.get("entries")) != TYPE_ARRAY:
		errors.append("%s: корень должен быть объектом с массивом 'entries'" % path)
		return
	if int(root.get("format", 0)) != SUPPORTED_FORMAT:
		errors.append("%s: неподдерживаемый format %s (нужен %d)" % [path, root.get("format"), SUPPORTED_FORMAT])
		return

	var schema: Dictionary = _schemas.get(category, {})
	if schema.is_empty():
		warnings.append("%s: нет схемы data/%s/%s.json, записи не проверяются" % [path, SCHEMA_DIR, category])
	if not _entries.has(category):
		_entries[category] = {}
		_order[category] = [] as Array[StringName]

	var entries: Array = root["entries"]
	for i in entries.size():
		var where := "%s[%d]" % [path, i]
		var raw: Variant = entries[i]
		if typeof(raw) == TYPE_DICTIONARY and typeof(raw.get("id")) == TYPE_STRING:
			where = "%s:%s" % [path, raw["id"]]
		var entry: Dictionary
		if schema.is_empty():
			entry = raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}
		else:
			entry = validator.validate_entry(raw, schema["fields"], where)
		if typeof(entry.get("id")) != TYPE_STRING:
			errors.append("%s: нет строкового 'id'" % where)
			continue
		var id := StringName(entry["id"])
		if _id_regex.search(entry["id"]) == null:
			errors.append("%s: id должен соответствовать %s" % [where, ID_PATTERN])
			continue
		var key := "%s:%s" % [category, id]
		if _sources.has(key):
			errors.append("%s: дубликат id '%s' (уже объявлен в %s)" % [path, id, _sources[key]])
			continue
		_sources[key] = path
		_entries[category][id] = entry
		_order[category].append(id)


func _resolve_refs(validator: SchemaValidator) -> void:
	for ref in validator.pending_refs:
		var ok := false
		for category in ref["to"]:
			if has_entry(category, ref["id"]):
				ok = true
				break
		if not ok:
			errors.append("%s: ссылка на несуществующий id '%s' (искали в %s)" % [
				ref["path"], ref["id"], ", ".join(ref["to"])])


func _build_blocks() -> void:
	var air := BlockDef.from_entry(0, {
		"id": "air", "name": { "ru": "Воздух", "en": "Air" }, "material": &"special",
		"render": &"invisible", "solid": false, "hardness": -1.0, "tool": &"none", "tool_tier": 0,
		"light_emission": 0, "light_color": Color.WHITE, "light_filter": 0, "flammable": false,
		"sounds": &"none", "map_color": Color(0, 0, 0, 0), "textures": {}, "drops": [], "tags": [],
	})
	_add_block(air)
	if not _entries.has("blocks"):
		return
	if not _schemas.has("blocks"):
		errors.append("нет схемы data/%s/blocks.json — блоки не загружены" % SCHEMA_DIR)
		return
	for id: StringName in _order["blocks"]:
		var e: Dictionary = _entries["blocks"][id]
		var where := "%s:%s" % [_sources["blocks:%s" % id], id]
		if id == AIR:
			errors.append("%s: id 'air' зарезервирован движком" % where)
			continue
		if not _check_block(e, where):
			continue
		if _blocks.size() >= MAX_BLOCKS:
			errors.append("%s: превышен лимит %d блоков" % [where, MAX_BLOCKS])
			return
		_add_block(BlockDef.from_entry(_blocks.size(), e))


## Смысловые проверки, которые не выражаются схемой.
func _check_block(e: Dictionary, where: String) -> bool:
	# После ошибок схемы части полей может не быть — не строим такой блок.
	for key: String in _schemas.get("blocks", {}).get("fields", {}):
		if not e.has(key) or e[key] == null:
			return false
	var tex: Dictionary = e["textures"]
	if not tex.has("all") and not (tex.has("top") and tex.has("bottom") and tex.has("side")):
		errors.append("%s: textures — нужен 'all' или все три 'top', 'bottom', 'side'" % where)
		return false
	for drop: Dictionary in e["drops"]:
		if drop.get("min", 0) > drop.get("max", 0):
			errors.append("%s: drops '%s' — min больше max" % [where, drop.get("id")])
			return false
	if e["render"] == &"opaque" and e["light_filter"] != 15:
		warnings.append("%s: непрозрачный блок с light_filter %d" % [where, e["light_filter"]])
	return true


func _add_block(b: BlockDef) -> void:
	_blocks.append(b)
	_block_nums[b.id] = b.num
	block_solid.append(1 if b.solid else 0)
	block_opaque.append(1 if b.opaque else 0)
	block_light_emission.append(b.light_emission)
	block_light_filter.append(b.light_filter)
	block_render.append(b.render_code())
	block_color.append(b.map_color)


func _parse_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		errors.append("%s: не удалось прочитать файл (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%d: ошибка JSON — %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _sorted_json_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "json":
			out.append(f)
	out.sort()
	return out
