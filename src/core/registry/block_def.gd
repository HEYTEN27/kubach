class_name BlockDef
extends RefCounted
## Определение блока после загрузки из data/blocks*.json.
##
## Числовой `num` годится только внутри одного запуска (чанки в памяти, мешер).
## На диск всегда пишется строковый `id` через палитру.

var num: int
var id: StringName
var name: Dictionary
var material: StringName
var render: StringName
var solid: bool
## Полностью закрывает соседние грани (для отсечения граней в мешере).
var opaque: bool
## Время ломания голыми руками, с. Отрицательное — неразрушаемый.
var hardness: float
var tool: StringName
var tool_tier: int
var light_emission: int
var light_color: Color
var light_filter: int
var flammable: bool
var sounds: StringName
var map_color: Color
var texture_top: StringName
var texture_bottom: StringName
var texture_side: StringName
var drops: Array
var tags: PackedStringArray


static func from_entry(p_num: int, e: Dictionary) -> BlockDef:
	var b := BlockDef.new()
	b.num = p_num
	b.id = StringName(e["id"])
	b.name = e["name"]
	b.material = e["material"]
	b.render = e["render"]
	b.solid = e["solid"]
	b.opaque = b.render == &"opaque"
	b.hardness = e["hardness"]
	b.tool = e["tool"]
	b.tool_tier = e["tool_tier"]
	b.light_emission = e["light_emission"]
	b.light_color = e["light_color"]
	b.light_filter = e["light_filter"]
	b.flammable = e["flammable"]
	b.sounds = e["sounds"]
	b.map_color = e["map_color"]
	var tex: Dictionary = e["textures"]
	var all: String = tex.get("all", "")
	b.texture_top = StringName(tex.get("top", all))
	b.texture_bottom = StringName(tex.get("bottom", all))
	b.texture_side = StringName(tex.get("side", all))
	b.drops = e["drops"]
	b.tags = PackedStringArray(e["tags"])
	return b


func is_breakable() -> bool:
	return hardness >= 0.0


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func display_name(locale: String = "ru") -> String:
	return name.get(locale, name.get("ru", String(id)))
