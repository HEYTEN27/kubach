class_name ItemTooltip
extends RefCounted
## Текст подсказки предмета (раздел 4.4): название, вид, качество, прочность, характеристики,
## свежесть еды, вес.

const KINDS := {
	&"block": "Блок", &"material": "Материал", &"tool": "Инструмент", &"weapon": "Оружие", &"armor": "Броня",
	&"clothing": "Одежда", &"backpack": "Рюкзак", &"accessory": "Украшение", &"shield": "Щит", &"light": "Свет",
	&"food": "Еда", &"misc": "Разное",
}
const SLOTS := {
	&"head": "голова", &"body": "тело", &"legs": "ноги", &"feet": "ступни", &"hands": "руки", &"back": "спина",
	&"accessory": "аксессуар", &"offhand": "вторая рука",
}
const TOOLS := { &"pickaxe": "кирка", &"shovel": "лопата", &"axe": "топор", &"hoe": "мотыга", &"shears": "ножницы",
	&"knife": "нож" }


static func lines(s: ItemStack, registry: ContentRegistry, locale: String = "ru") -> Array[String]:
	var out: Array[String] = []
	var d := registry.item(s.id)
	if d == null:
		out.append(String(s.id))
		return out
	out.append(d.display_name(locale))
	var kind := String(KINDS.get(d.kind, d.kind))
	if d.equip != ItemDef.EQUIP_NONE:
		kind += " · слот: %s" % SLOTS.get(d.equip, d.equip)
	out.append(kind)
	if s.data.has("quality"):
		out.append("Качество: %d%%" % roundi(float(s.data["quality"]) * 100.0))
	if d.durability > 0:
		out.append("Прочность: %d / %d" % [int(s.data.get("durability", d.durability)), d.durability])
	if d.is_tool():
		out.append("Инструмент: %s, уровень %d, скорость ×%.1f" % [TOOLS.get(d.tool["type"], d.tool["type"]),
			int(d.tool.get("tier", 0)), float(d.tool.get("speed", 1.0))])
	if d.damage > 0.0:
		out.append("Урон: %.0f" % d.damage)
	if d.armor > 0.0:
		out.append("Защита: %.1f" % d.armor)
	if d.insulation != 0.0:
		out.append("Тепло: %+.0f °C" % d.insulation)
	if d.water_resist > 0.0:
		out.append("Влагостойкость: %d%%" % roundi(d.water_resist * 100.0))
	if d.backpack_slots > 0:
		out.append("Ячеек: +%d" % d.backpack_slots)
	if d.light > 0:
		out.append("Свет: %d" % d.light)
	if d.is_food():
		out.append("Сытость: %.0f · вода: %+.0f" % [float(d.food.get("nutrition", 0.0)), float(d.food.get("thirst", 0.0))])
		if s.data.has("freshness"):
			out.append("Свежесть: %d%%" % roundi(float(s.data["freshness"]) * 100.0))
	var block := registry.block(d.id) if d.is_block() else null
	if block != null and block.container_slots > 0:
		out.append("Хранилище: %d ячеек" % block.container_slots)
	var contents: Variant = s.data.get("contents")
	if contents is Array and not (contents as Array).is_empty():
		var n := 0
		for c: Variant in contents:
			if c != null:
				n += 1
		out.append("Внутри: %d стоп." % n)
	if s.data.has("color"):
		out.append("Цвет: %s" % String(s.data["color"]))
	if s.count > 1:
		out.append("Вес: %.2f кг × %d = %.1f кг" % [d.weight, s.count, d.weight * s.count])
	else:
		out.append("Вес: %.2f кг" % d.weight)
	return out
