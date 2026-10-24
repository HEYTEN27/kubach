class_name GameSettings
extends Node
## Настройки игрока (автозагрузка `Settings`). Этап 3 — графика: пресет из
## data/graphics_presets.json плюс личные правки («Свои»). Хранятся в user://settings.cfg.
## Экран настроек — этап 4; сейчас пресет меняется аргументом --preset или из кода.

const PATH := "user://settings.cfg"
const CUSTOM := &"custom"
const DEFAULT_PRESET := &"high"

signal graphics_changed(graphics: Dictionary)

## Текущий пресет графики (id из graphics_presets или CUSTOM).
var preset: StringName = DEFAULT_PRESET
## Действующие значения графики (поля схемы graphics_presets, без id/name/order).
var graphics := {}
var _overrides := {}


func _ready() -> void:
	load_settings()


## Значения пресета без служебных полей. Пустой словарь — пресета нет.
static func preset_values(registry: ContentRegistry, id: StringName) -> Dictionary:
	if registry == null or not registry.has_entry("graphics_presets", id):
		return {}
	var v := registry.get_entry("graphics_presets", id).duplicate()
	for k in ["id", "name", "order"]:
		v.erase(k)
	return v


## Список пресетов по порядку: [id, ...].
static func preset_ids(registry: ContentRegistry) -> Array[StringName]:
	var list := registry.get_entries("graphics_presets")
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	var out: Array[StringName] = []
	for e in list:
		out.append(StringName(e["id"]))
	return out


func load_settings(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	_overrides = {}
	preset = DEFAULT_PRESET
	if cfg.load(path) == OK:
		preset = StringName(cfg.get_value("graphics", "preset", String(DEFAULT_PRESET)))
		if cfg.has_section("graphics_custom"):
			for k in cfg.get_section_keys("graphics_custom"):
				_overrides[k] = cfg.get_value("graphics_custom", k)
	_rebuild()


func save_settings(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", String(preset))
	for k: String in _overrides:
		cfg.set_value("graphics_custom", k, _overrides[k])
	return cfg.save(path)


## Выбрать пресет: личные правки сбрасываются.
func set_preset(id: StringName) -> void:
	preset = id
	_overrides = {}
	_rebuild()


## Изменить одно значение: пресет становится «Свои».
func set_graphics(key: String, value: Variant) -> void:
	if preset != CUSTOM:
		_overrides["_base"] = String(preset)
	_overrides[key] = value
	preset = CUSTOM
	_rebuild()


func _registry() -> ContentRegistry:
	return get_node_or_null("/root/Registry") as ContentRegistry


func _rebuild() -> void:
	var reg := _registry()
	var base_id := preset
	if base_id == CUSTOM or preset_values(reg, base_id).is_empty():
		base_id = StringName(_overrides.get("_base", String(DEFAULT_PRESET)))
	graphics = preset_values(reg, base_id)
	if graphics.is_empty():
		graphics = preset_values(reg, DEFAULT_PRESET)
	for k: String in _overrides:
		if not k.begins_with("_"):
			graphics[k] = _overrides[k]
	graphics_changed.emit(graphics)
