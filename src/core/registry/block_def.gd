class_name BlockDef
extends RefCounted
## Определение блока после загрузки из data/blocks*.json.
##
## Числовой `num` годится только внутри одного запуска (чанки в памяти, мешер).
## На диск всегда пишется строковый `id` через палитру.

## Коды `render` для плоского массива Registry.block_render (мешер).
const RENDER_INVISIBLE := 0
const RENDER_OPAQUE := 1
const RENDER_CUTOUT := 2
const RENDER_TRANSLUCENT := 3
const RENDER_LIQUID := 4
const RENDER_CODES := { &"invisible": 0, &"opaque": 1, &"cutout": 2, &"translucent": 3, &"liquid": 4 }
## Коды формы (Registry.block_shape).
const SHAPE_CUBE := 0
const SHAPE_CROSS := 1
const SHAPE_LAYER := 2
const SHAPE_CODES := { &"cube": 0, &"cross": 1, &"layer": 2 }
## Коды тонирования (Registry.block_tint).
const TINT_NONE := 0
const TINT_GRASS := 1
const TINT_FOLIAGE := 2
const TINT_CODES := { &"none": 0, &"grass": 1, &"foliage": 2 }

var num: int
var id: StringName
var name: Dictionary
var material: StringName
var render: StringName
var shape: StringName
var layer_height: float
var solid: bool
## Полностью закрывает соседние грани (для отсечения граней в мешере): непрозрачный куб.
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
var tint: StringName
var tint_strength: float
var texture_top: StringName
var texture_bottom: StringName
var texture_side: StringName
var drops: Array
var tags: PackedStringArray
## Хранилище: число ячеек (0 — не контейнер) и вид (chest, dresser, barrel, crate, shelf).
var container_slots := 0
var container_kind: StringName = &""
## Есть ли у блока предмет (воды, лавы, материнской породы в инвентаре нет).
var has_item := true
var weight := 1.0
## Выживание (этап 5): тепло рядом с блоком, °C; урон в секунду внутри блока.
var heat := 0.0
var contact_damage := 0.0
## Кровать: kind (none, sleeping_bag, bed, double_bed) и rest.
var bed := {}
## Ремесло (этап 6): вид станции (data/stations.json) и уровень (наковальни); модель из
## коробок вместо куба — [{ from: Vector3, to: Vector3 (в блоках), tex: StringName, anim }];
## топливо { heat, minutes }.
var station_kind: StringName = &""
var station_tier := 0
var model: Array = []
var fuel := {}
## Съедобные растения и лекарственные травы: те же поля, что у предметов.
var food := {}
var medicine := {}


static func from_entry(p_num: int, e: Dictionary) -> BlockDef:
	var b := BlockDef.new()
	b.num = p_num
	b.id = StringName(e["id"])
	b.name = e["name"]
	b.material = e["material"]
	b.render = e["render"]
	b.shape = e.get("shape", &"cube")
	b.layer_height = e.get("layer_height", 1.0)
	b.solid = e["solid"]
	b.opaque = b.render == &"opaque" and b.shape == &"cube"
	b.hardness = e["hardness"]
	b.tool = e["tool"]
	b.tool_tier = e["tool_tier"]
	b.light_emission = e["light_emission"]
	b.light_color = e["light_color"]
	b.light_filter = e["light_filter"]
	b.flammable = e["flammable"]
	b.sounds = e["sounds"]
	b.map_color = e["map_color"]
	b.tint = e.get("tint", &"none")
	b.tint_strength = e.get("tint_strength", 0.0)
	var tex: Dictionary = e["textures"]
	var all: String = tex.get("all", "")
	b.texture_top = StringName(tex.get("top", all))
	b.texture_bottom = StringName(tex.get("bottom", all))
	b.texture_side = StringName(tex.get("side", all))
	b.drops = e["drops"]
	b.tags = PackedStringArray(e["tags"])
	var cont: Dictionary = e.get("container", {})
	b.container_slots = int(cont.get("slots", 0))
	b.container_kind = StringName(cont.get("kind", "")) if b.container_slots > 0 else &""
	b.has_item = e.get("item", true) and b.render != &"liquid" and b.is_breakable()
	b.weight = e.get("weight", 1.0)
	b.heat = e.get("heat", 0.0)
	b.contact_damage = e.get("contact_damage", 0.0)
	var bd: Dictionary = e.get("bed", {})
	b.bed = bd if String(bd.get("kind", "none")) != "none" else {}
	b.food = _non_empty(e.get("food", {}))
	b.medicine = _non_empty(e.get("medicine", {}))
	var st: Dictionary = e.get("station", {})
	b.station_kind = StringName(st.get("kind", ""))
	b.station_tier = int(st.get("tier", 1)) if b.station_kind != &"" else 0
	for m: Dictionary in e.get("model", []):
		var f: Array = m.get("from", [0, 0, 0])
		var t: Array = m.get("to", [16, 16, 16])
		b.model.append({ "from": Vector3(f[0], f[1], f[2]) / 16.0, "to": Vector3(t[0], t[1], t[2]) / 16.0,
			"tex": StringName(m.get("tex", "")), "anim": StringName(m.get("anim", "")) })
	var fu: Dictionary = e.get("fuel", {})
	b.fuel = fu if float(fu.get("minutes", 0.0)) > 0.0 else {}
	return b


static func _non_empty(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	if float(d.get("nutrition", 0.0)) == 0.0 and float(d.get("thirst", 0.0)) == 0.0 and (d.get("cures", []) as Array).is_empty() and float(d.get("heal", 0.0)) == 0.0 and (d.get("applies", []) as Array).is_empty() and (d.get("effects", []) as Array).is_empty():
		return {}
	return d


## Станция ремесла.
func is_station() -> bool:
	return station_kind != &""


## Рисуется моделью из коробок (ModelMesher), а не кубом.
func has_model() -> bool:
	return not model.is_empty()


## Кровать или спальник.
func is_bed() -> bool:
	return not bed.is_empty()


func render_code() -> int:
	return RENDER_CODES[render]


func shape_code() -> int:
	return SHAPE_CODES[shape]


func tint_code() -> int:
	return TINT_CODES[tint]


func is_breakable() -> bool:
	return hardness >= 0.0


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Язык названий по умолчанию (настройка «Язык»).
static var locale := "ru"


func display_name(p_locale: String = "") -> String:
	var l := p_locale if p_locale != "" else locale
	return name.get(l, name.get("ru", String(id)))
