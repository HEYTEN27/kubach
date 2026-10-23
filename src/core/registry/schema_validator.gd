class_name SchemaValidator
extends RefCounted
## Проверяет записи из data/*.json по схемам из data/schemas/ и подставляет значения по умолчанию.
##
## Формат схемы описан в data/README.md. Ссылки (`"type": "ref"`) не проверяются сразу:
## они копятся в `pending_refs` и разрешаются реестром, когда загружены все категории.

const LOCALES: PackedStringArray = ["ru", "en"]
const KNOWN_TYPES: PackedStringArray = [
	"string", "int", "float", "bool", "enum", "localized", "color", "object", "array", "ref",
]

var errors: PackedStringArray = []
## Элементы: { "path": String, "id": String, "to": PackedStringArray }.
var pending_refs: Array[Dictionary] = []

var _regex_cache := {}


## Проверяет саму схему: известные типы, наличие `values`/`fields`/`of`/`to` где нужно.
func check_fields_spec(fields: Variant, path: String) -> bool:
	if typeof(fields) != TYPE_DICTIONARY:
		_err("%s: 'fields' должен быть объектом" % path)
		return false
	var ok := true
	for key: String in fields:
		ok = check_value_spec(fields[key], "%s.%s" % [path, key]) and ok
	return ok


func check_value_spec(spec: Variant, path: String) -> bool:
	if typeof(spec) != TYPE_DICTIONARY or not spec.has("type"):
		_err("%s: у поля схемы нет 'type'" % path)
		return false
	var t: String = spec["type"]
	if t not in KNOWN_TYPES:
		_err("%s: неизвестный тип '%s'" % [path, t])
		return false
	match t:
		"enum":
			if typeof(spec.get("values")) != TYPE_ARRAY or spec["values"].is_empty():
				_err("%s: у enum нет списка 'values'" % path)
				return false
		"object":
			return check_fields_spec(spec.get("fields"), path)
		"array":
			if not spec.has("of"):
				_err("%s: у array нет 'of'" % path)
				return false
			return check_value_spec(spec["of"], path + "[]")
		"ref":
			if typeof(spec.get("to")) != TYPE_ARRAY or spec["to"].is_empty():
				_err("%s: у ref нет списка категорий 'to'" % path)
				return false
		"string":
			if spec.has("pattern") and _regex(spec["pattern"]) == null:
				_err("%s: некорректный pattern '%s'" % [path, spec["pattern"]])
				return false
	return true


## Возвращает нормализованную копию записи: значения приведены к типам, пропуски заполнены
## значениями по умолчанию. Ошибки пишутся в `errors`.
func validate_entry(entry: Variant, fields: Dictionary, path: String) -> Dictionary:
	var out := {}
	if typeof(entry) != TYPE_DICTIONARY:
		_err("%s: ожидался объект, получено %s" % [path, type_string(typeof(entry))])
		return out
	for key: String in entry:
		if not fields.has(key):
			_err("%s: неизвестное поле '%s'" % [path, key])
	for key: String in fields:
		var spec: Dictionary = fields[key]
		var field_path := "%s.%s" % [path, key]
		if entry.has(key):
			out[key] = validate_value(entry[key], spec, field_path)
		elif spec.get("required", false):
			_err("%s: обязательное поле отсутствует" % field_path)
		elif spec.has("default"):
			var default_value: Variant = spec["default"]
			if default_value is Array or default_value is Dictionary:
				default_value = default_value.duplicate(true)
			out[key] = validate_value(default_value, spec, field_path + " (default)")
	return out


func validate_value(value: Variant, spec: Dictionary, path: String) -> Variant:
	match spec["type"]:
		"string":
			if typeof(value) != TYPE_STRING:
				return _type_err(path, "строка", value)
			if spec.has("pattern") and _regex(spec["pattern"]).search(value) == null:
				_err("%s: '%s' не соответствует шаблону %s" % [path, value, spec["pattern"]])
			return value
		"int":
			if not _is_number(value) or float(value) != floorf(float(value)):
				return _type_err(path, "целое число", value)
			_check_range(float(value), spec, path)
			return int(value)
		"float":
			if not _is_number(value):
				return _type_err(path, "число", value)
			_check_range(float(value), spec, path)
			return float(value)
		"bool":
			if typeof(value) != TYPE_BOOL:
				return _type_err(path, "true/false", value)
			return value
		"enum":
			if typeof(value) != TYPE_STRING or value not in spec["values"]:
				_err("%s: '%s' не входит в %s" % [path, str(value), str(spec["values"])])
				return null
			return StringName(value)
		"localized":
			if typeof(value) != TYPE_DICTIONARY:
				return _type_err(path, "объект {ru, en}", value)
			for locale in LOCALES:
				if typeof(value.get(locale)) != TYPE_STRING or String(value[locale]).is_empty():
					_err("%s: нет перевода '%s'" % [path, locale])
			return value
		"color":
			if typeof(value) != TYPE_STRING or not Color.html_is_valid(value):
				return _type_err(path, "цвет #rrggbb", value)
			return Color.html(value)
		"object":
			return validate_entry(value, spec["fields"], path)
		"array":
			if typeof(value) != TYPE_ARRAY:
				return _type_err(path, "массив", value)
			var out := []
			for i in value.size():
				out.append(validate_value(value[i], spec["of"], "%s[%d]" % [path, i]))
			return out
		"ref":
			if typeof(value) != TYPE_STRING:
				return _type_err(path, "строковый id", value)
			pending_refs.append({ "path": path, "id": value, "to": PackedStringArray(spec["to"]) })
			return StringName(value)
	_err("%s: неизвестный тип '%s'" % [path, spec["type"]])
	return null


func _check_range(v: float, spec: Dictionary, path: String) -> void:
	if spec.has("min") and v < float(spec["min"]):
		_err("%s: %s меньше минимума %s" % [path, v, spec["min"]])
	if spec.has("max") and v > float(spec["max"]):
		_err("%s: %s больше максимума %s" % [path, v, spec["max"]])


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _type_err(path: String, expected: String, got: Variant) -> Variant:
	_err("%s: ожидалось %s, получено %s" % [path, expected, JSON.stringify(got)])
	return null


func _regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var re := RegEx.new()
		_regex_cache[pattern] = re if re.compile(pattern) == OK else null
	return _regex_cache[pattern]


func _err(msg: String) -> void:
	errors.append(msg)
