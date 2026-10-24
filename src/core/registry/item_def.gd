class_name ItemDef
extends RefCounted
## Определение предмета (раздел 4.4 ТЗ). Предметы берутся из data/items.json и из блоков:
## у каждого блока с item = true есть предмет с тем же id (ставит этот блок).

const EQUIP_NONE := &"none"

var id: StringName
var name: Dictionary
## material, tool, weapon, armor, clothing, backpack, accessory, shield, light, food, misc, block.
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
## { nutrition, thirst, spoil_days } или пусто.
var food := {}
var light := 0
var light_color := Color.WHITE
## Числовой ID блока, который ставит предмет; 0 — не ставится.
var place_block := 0
## Внешний вид на модели персонажа: { color, style }.
var model := {}
var icon := {}
var tags: PackedStringArray = []


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
	d.food = e.get("food", {})
	d.light = e["light"]
	d.light_color = e["light_color"]
	var place: String = e.get("place", "")
	d.place_block = maxi(0, registry.block_num(StringName(place))) if place != "" else 0
	d.model = e.get("model", {})
	d.icon = e.get("icon", {})
	d.tags = PackedStringArray(e["tags"])
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
	return d


## Язык названий по умолчанию (настройка «Язык»).
static var locale := "ru"


func display_name(p_locale: String = "") -> String:
	var l := p_locale if p_locale != "" else locale
	return name.get(l, name.get("ru", String(id)))


func is_block() -> bool:
	return kind == &"block"


func is_tool() -> bool:
	return not tool.is_empty()


func is_food() -> bool:
	return not food.is_empty()
