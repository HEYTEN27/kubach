class_name GameSettings
extends Node
## Настройки игрока (автозагрузка `Settings`, раздел 19 ТЗ). Все настройки описаны в
## data/settings.json; по нему строится экран настроек. Графика — пресет из
## data/graphics_presets.json плюс личные правки («Свои»). Переназначенные клавиши — в
## разделе bindings. Всё хранится в user://settings.cfg.
##
## Глобальное применяется здесь: окно, VSync, лимит FPS, масштаб и тема интерфейса, громкость
## шин, моно, фильтр гаммы/яркости/дальтонизма, язык названий. Остальное читают системы
## через get_value() и сигнал setting_changed.

const PATH := "user://settings.cfg"
const CUSTOM := &"custom"
const DEFAULT_PRESET := &"high"
const AUDIO_BUSES := { "vol_master": "Master", "vol_music": "Music", "vol_sfx": "SFX", "vol_ambience": "Ambience",
	"vol_voice": "Voice", "vol_ui": "UI" }

signal graphics_changed(graphics: Dictionary)
signal setting_changed(id: String, value: Variant)

## Текущий пресет графики (id из graphics_presets или CUSTOM).
var preset: StringName = DEFAULT_PRESET
## Действующие значения графики (поля схемы graphics_presets, без id/name/order).
var graphics := {}
## Переназначенные действия: имя действия → массив строк событий (см. Controls).
var bindings := {}
var _overrides := {}
var _values := {}
var _defs := {}
var _filter: CanvasLayer
var _filter_rect: ColorRect
var _path := PATH


func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply_all()


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


## Описания настроек раздела (из data/settings.json) по порядку.
func definitions(section: String = "") -> Array[Dictionary]:
	var reg := _registry()
	var out: Array[Dictionary] = []
	if reg == null:
		return out
	for e in reg.get_entries("settings"):
		if section == "" or String(e["section"]) == section:
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return out


func definition(id: String) -> Dictionary:
	if _defs.is_empty():
		for e in definitions():
			_defs[String(e["id"])] = e
	return _defs.get(id, {})


## Значение по умолчанию из описания, приведённое к типу.
func default_value(id: String) -> Variant:
	var d := definition(id)
	if d.is_empty():
		return null
	return parse_value(d, String(d["default"]))


static func parse_value(d: Dictionary, text: String) -> Variant:
	match String(d["type"]):
		"bool":
			return text == "true"
		"int":
			return int(text)
		"float":
			return float(text)
	return text


## Текущее значение настройки (графика — из действующего пресета).
func get_value(id: String) -> Variant:
	if id == "graphics_preset":
		return String(preset)
	var d := definition(id)
	if not d.is_empty() and d.get("preset_key", false) and graphics.has(id):
		return graphics[id]
	if _values.has(id):
		return _values[id]
	return default_value(id)


func set_value(id: String, value: Variant) -> void:
	if id == "graphics_preset":
		set_preset(StringName(String(value)))
		setting_changed.emit(id, value)
		return
	var d := definition(id)
	if not d.is_empty() and d.get("preset_key", false):
		var cur: Variant = graphics.get(id)
		if cur is int:
			value = int(value)
		elif cur is float:
			value = float(value)
		elif cur is bool:
			value = bool(value)
		elif cur is String:
			value = String(value)
		set_graphics(id, value)
		setting_changed.emit(id, value)
		return
	_values[id] = value
	_apply_one(id)
	setting_changed.emit(id, value)


func load_settings(path: String = PATH) -> void:
	_path = path
	var cfg := ConfigFile.new()
	_overrides = {}
	_values = {}
	bindings = {}
	preset = DEFAULT_PRESET
	if cfg.load(path) == OK:
		preset = StringName(cfg.get_value("graphics", "preset", String(DEFAULT_PRESET)))
		if cfg.has_section("graphics_custom"):
			for k in cfg.get_section_keys("graphics_custom"):
				_overrides[k] = cfg.get_value("graphics_custom", k)
		if cfg.has_section("settings"):
			for k in cfg.get_section_keys("settings"):
				_values[k] = cfg.get_value("settings", k)
		if cfg.has_section("bindings"):
			for k in cfg.get_section_keys("bindings"):
				bindings[k] = cfg.get_value("bindings", k)
	_rebuild()


func save_settings(path: String = "") -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", String(preset))
	for k: String in _overrides:
		cfg.set_value("graphics_custom", k, _overrides[k])
	for k: String in _values:
		cfg.set_value("settings", k, _values[k])
	for k: String in bindings:
		cfg.set_value("bindings", k, bindings[k])
	return cfg.save(path if path != "" else _path)


## Выбрать пресет: личные правки графики сбрасываются.
func set_preset(id: StringName) -> void:
	preset = id
	_overrides = {}
	_rebuild()


## Изменить одно значение графики: пресет становится «Свои».
func set_graphics(key: String, value: Variant) -> void:
	if preset != CUSTOM:
		_overrides["_base"] = String(preset)
	_overrides[key] = value
	preset = CUSTOM
	_rebuild()


## Сбросить раздел к значениям по умолчанию.
func reset_section(section: String) -> void:
	if section == "graphics":
		set_preset(DEFAULT_PRESET)
		return
	if section == "controls":
		bindings.clear()
		var c := get_node_or_null(^"/root/Controls")
		if c:
			c.call(&"reapply")
	for d in definitions(section):
		_values.erase(String(d["id"]))
	apply_all()
	for d in definitions(section):
		setting_changed.emit(String(d["id"]), get_value(String(d["id"])))


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


# ---------------------------------------------------------------------------------------------
# Применение глобальных настроек

func apply_all() -> void:
	for id in ["window_mode", "vsync", "fps_limit", "ui_scale", "font_size", "high_contrast", "mono", "language",
			"colorblind"]:
		_apply_one(id)
	for id: String in AUDIO_BUSES:
		_apply_one(id)


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _apply_one(id: String) -> void:
	var v: Variant = get_value(id)
	if AUDIO_BUSES.has(id):
		var bus := AudioServer.get_bus_index(AUDIO_BUSES[id])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(v) / 100.0, 0.0001)))
			AudioServer.set_bus_mute(bus, float(v) <= 0.0)
		return
	match id:
		"window_mode", "resolution":
			if _headless():
				return
			var mode := String(get_value("window_mode"))
			var win := get_window()
			if mode == "fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			elif mode == "borderless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				var res := String(get_value("resolution")).split("x")
				if res.size() == 2 and id == "resolution":
					win.size = Vector2i(int(res[0]), int(res[1]))
		"vsync":
			if not _headless():
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"fps_limit":
			Engine.max_fps = int(String(v))
		"ui_scale":
			if not _headless():
				get_window().content_scale_factor = clampf(float(v), 0.5, 2.0)
		"font_size", "high_contrast":
			get_tree().root.theme = UiTheme.build(float(get_value("font_size")), bool(get_value("high_contrast")))
		"mono":
			var master := AudioServer.get_bus_index("Master")
			for i in AudioServer.get_bus_effect_count(master):
				if AudioServer.get_bus_effect(master, i) is AudioEffectStereoEnhance:
					AudioServer.set_bus_effect_enabled(master, i, bool(v))
		"language":
			BlockDef.locale = String(v)
			ItemDef.locale = String(v)
		"colorblind", "gamma", "brightness":
			_update_filter()


## Шины звука: Music, SFX, Ambience, Voice, UI (все в Master); на Master — моно-сведение.
func _ensure_buses() -> void:
	for bus_name: String in AUDIO_BUSES.values():
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var master := AudioServer.get_bus_index("Master")
	var has_mono := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectStereoEnhance:
			has_mono = true
	if not has_mono:
		var fx := AudioEffectStereoEnhance.new()
		fx.pan_pullout = 0.0
		AudioServer.add_bus_effect(master, fx)
		AudioServer.set_bus_effect_enabled(master, AudioServer.get_bus_effect_count(master) - 1, false)


## Экранный фильтр: гамма, яркость, коррекция для дальтонизма (поверх всего, в том числе UI).
func _update_filter() -> void:
	var cb := String(get_value("colorblind"))
	var gamma := float(get_value("gamma"))
	var bright := float(get_value("brightness"))
	var needed := cb != "none" or absf(gamma - 1.0) > 0.001 or absf(bright - 1.0) > 0.001
	if not needed:
		if _filter != null:
			_filter.visible = false
		return
	if _filter == null:
		_filter = CanvasLayer.new()
		_filter.layer = 120
		_filter_rect = ColorRect.new()
		_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://src/ui/theme/screen_filter.gdshader") as Shader
		_filter_rect.material = mat
		_filter.add_child(_filter_rect)
		add_child(_filter)
	_filter.visible = true
	var m := _filter_rect.material as ShaderMaterial
	m.set_shader_parameter(&"gamma", gamma)
	m.set_shader_parameter(&"brightness", bright)
	m.set_shader_parameter(&"mode", ["none", "protanopia", "deuteranopia", "tritanopia"].find(cb))
