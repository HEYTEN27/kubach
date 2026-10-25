class_name ItemIcons
extends RefCounted
## Иконки предметов из атласа tools/texgen/icons.py (items_icons.png + items_icons.json).
## Иконка — AtlasTexture (кэшируется). Нет иконки — серый квадрат-заглушка.

const PNG := "res://assets/textures/generated/items_icons.png"
const JSON_PATH := "res://assets/textures/generated/items_icons.json"

static var _shared: ItemIcons
static var _registry: ContentRegistry

var _atlas: Texture2D
var _size := 64
var _columns := 16
var _index := {}
var _cache := {}
var _fallback: Texture2D


## Общий экземпляр (атлас грузится один раз).
static func shared() -> ItemIcons:
	if _shared == null:
		_shared = ItemIcons.new()
	return _shared


## Реестр для подсказок и полосок прочности (автозагрузка Registry, если есть).
static func registry() -> ContentRegistry:
	if _registry == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			_registry = tree.root.get_node_or_null(^"Registry") as ContentRegistry
	return _registry


func _init() -> void:
	if ResourceLoader.exists(PNG):
		_atlas = load(PNG) as Texture2D
	var f := FileAccess.open(JSON_PATH, FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_size = int(d.get("size", 64))
			_columns = int(d.get("columns", 16))
			_index = d.get("icons", {})
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0.8))
	_fallback = ImageTexture.create_from_image(img)


func has_icon(id: StringName) -> bool:
	return _index.has(String(id))


## Иконка стопки: у частей и инструментов из частей — вариант по материалу («pickaxe@steel»).
func icon_for(s: ItemStack) -> Texture2D:
	var mat := ""
	if s.data.has("material"):
		mat = String(s.data["material"])
	elif s.data.get("parts") is Dictionary:
		mat = String(s.data["parts"].get("head", {}).get("material", ""))
	if mat != "":
		var key := StringName("%s@%s" % [s.id, mat])
		if has_icon(key):
			return icon(key)
	return icon(s.id)


func icon(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var i: Variant = _index.get(String(id))
	if _atlas == null or i == null:
		return _fallback
	var t := AtlasTexture.new()
	t.atlas = _atlas
	var n := int(i)
	t.region = Rect2((n % _columns) * _size, (n / _columns) * _size, _size, _size)
	_cache[id] = t
	return t
