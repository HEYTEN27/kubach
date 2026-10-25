class_name ItemDef
extends RefCounted
## Определение предмета (раздел 4.4 ТЗ). Предметы берутся из data/items.json и из блоков:
## у каждого блока с item = true есть предмет с тем же id (ставит этот блок).

const EQUIP_NONE := &"none"

var id: StringName
var name: Dictionary
## material, tool, weapon, armor, clothing, backpack, accessory, shield, light, food, misc, block, part.
var kind: StringName
var stack := 64
var weight := 0.1
var durability := 0
var quality := false
## Слот экипировки: head, body, legs, feet, hands, back, accessory, offhand или none.
var equip: StringName = EQUIP_NONE
var backpack_slots := 0
## { type, tier, speed } или пусто.
var tool := {}
var damage := 0.0
var armor := 0.0
var insulation := 0.0
var water_resist := 0.0
## { nutrition, thirst, spoil_days, hot, eat_seconds, effects } или пусто.
var food := {}
## { cures, chance, heal, applies } или пусто.
var medicine := {}
var light := 0
var light_color := Color.WHITE
## Числовой ID блока, который ставит предмет; 0 — не ставится.
var place_block := 0
## Внешний вид на модели персонажа: { color, style }.
var model := {}
var icon := {}
var tags: PackedStringArray = []
## Ремесло (этап 6): топливо { heat, minutes }, цвет красителя, рецепты чертежа.
var fuel := {}
var dye := ""
var unlocks: PackedStringArray = []
## Часть инструмента (id из data/parts.json) — материал и качество лежат в данных стопки.
var part: StringName = &""
## Инструмент из частей (id из data/tool_types.json) — свойства считаются по частям.
var assembly: StringName = &""


static func from_entry(e: Dictionary, registry: ContentRegistry) -> ItemDef:
	var d := ItemDef.new()
	d.id = StringName(e["id"])
	d.name = e["name"]
	d.kind = e["kind"]
	d.stack = e["stack"]
	d.weight = e["weight"]
	d.durability = e["durability"]
	d.quality = e["quality"]
	d.equip = e["equip"]
	d.backpack_slots = e["backpack_slots"]
	d.tool = e.get("tool", {})
	d.damage = e["damage"]
	d.armor = e["armor"]
	d.insulation = e["insulation"]
	d.water_resist = e["water_resist"]
	d.food = BlockDef._non_empty(e.get("food", {}))
	d.medicine = BlockDef._non_empty(e.get("medicine", {}))
	d.light = e["light"]
	d.light_color = e["light_color"]
	var place: String = e.get("place", "")
	d.place_block = maxi(0, registry.block_num(StringName(place))) if place != "" else 0
	d.model = e.get("model", {})
	d.icon = e.get("icon", {})
	d.tags = PackedStringArray(e["tags"])
	var fu: Dictionary = e.get("fuel", {})
	d.fuel = fu if float(fu.get("minutes", 0.0)) > 0.0 else {}
	d.dye = String(e.get("dye", ""))
	d.unlocks = PackedStringArray(e.get("unlocks", []))
	if d.stack > 1 and (d.durability > 0 or d.equip != EQUIP_NONE):
		d.stack = 1
	return d


## Предмет блока: ставит сам блок, стак 64, свет — если блок светится (факел).
static func from_block(b: BlockDef) -> ItemDef:
	var d := ItemDef.new()
	d.id = b.id
	d.name = b.name
	d.kind = &"block"
	d.weight = b.weight
	d.place_block = b.num
	d.light = b.light_emission
	d.light_color = b.light_color
	if b.light_emission > 0:
		d.equip = &"offhand"
		d.stack = 64
	d.tags = b.tags
	d.food = b.food
	d.medicine = b.medicine
	d.fuel = b.fuel
	return d


## Предмет-часть (навершие, рукоять, обмотка): материал и качество — в данных стопки.
static func from_part(e: Dictionary) -> ItemDef:
	var d := ItemDef.new()
	d.id = StringName(e["id"])
	d.name = e["name"]
	d.kind = &"part"
	d.stack = 16
	d.weight = 0.3 * float(e.get("units", 1)) * float(e.get("weight", 1.0))
	d.quality = true
	d.part = d.id
	d.icon = e.get("icon", {})
	d.tags = PackedStringArray(["part", String(e.get("slot", ""))])
	return d


## Инструмент или оружие из частей: прочность, скорость и урон — по частям (ToolAssembly).
static func from_tool_type(e: Dictionary) -> ItemDef:
	var d := ItemDef.new()
	d.id = StringName(e["id"])
	d.name = e["name"]
	d.kind = StringName(e.get("kind", "tool"))
	d.stack = 1
	d.weight = 1.0
	d.durability = int(e.get("durability", 100))
	d.quality = true
	d.damage = float(e.get("damage", 1.0))
	d.assembly = d.id
	var t := String(e.get("tool", "none"))
	if t != "none":
		d.tool = { "type": StringName(t), "tier": 1, "speed": 1.0 }
	d.icon = e.get("icon", {})
	d.tags = PackedStringArray(["assembled"])
	return d


## Язык названий по умолчанию (настройка «Язык»).
static var locale := "ru"


func display_name(p_locale: String = "") -> String:
	var l := p_locale if p_locale != "" else locale
	return name.get(l, name.get("ru", String(id)))


func is_block() -> bool:
	return kind == &"block"


func is_part() -> bool:
	return part != &""


func is_assembled() -> bool:
	return assembly != &""


func is_fuel() -> bool:
	return not fuel.is_empty()


func is_tool() -> bool:
	return not tool.is_empty()


func is_food() -> bool:
	return not food.is_empty()


func is_medicine() -> bool:
	return not medicine.is_empty()


## Можно употребить (съесть, выпить или применить): еда или лекарство.
func is_consumable() -> bool:
	return is_food() or is_medicine()
