class_name ItemTooltip
extends RefCounted
## Текст подсказки предмета (раздел 4.4): название, вид, качество, прочность, характеристики,
## свежесть еды, вес.

const KINDS := {
	&"block": "Блок", &"material": "Материал", &"tool": "Инструмент", &"weapon": "Оружие", &"armor": "Броня",
	&"clothing": "Одежда", &"backpack": "Рюкзак", &"accessory": "Украшение", &"shield": "Щит", &"light": "Свет",
	&"food": "Еда", &"misc": "Разное", &"part": "Часть инструмента",
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
	var data := CraftingData.shared(registry)
	out.append(ToolAssembly.display_name(s, d, data, locale))
	var kind := String(KINDS.get(d.kind, d.kind))
	if d.equip != ItemDef.EQUIP_NONE:
		kind += " · слот: %s" % SLOTS.get(d.equip, d.equip)
	out.append(kind)
	if s.data.has("quality"):
		out.append("Качество: %s" % data.quality_name(int(s.data["quality"]), locale))
	var mx := s.max_durability(d)
	if mx > 0:
		out.append("Прочность: %d / %d" % [int(s.data.get("durability", mx)), mx])
	var tool := ToolAssembly.tool_of(s, d)
	if not tool.is_empty():
		out.append("Инструмент: %s, уровень %d, скорость ×%.1f" % [TOOLS.get(tool["type"], tool["type"]),
			int(tool.get("tier", 0)), float(tool.get("speed", 1.0))])
	var dmg := ToolAssembly.damage_of(s, d)
	if dmg > 0.0:
		out.append("Урон: %.1f" % dmg)
	if s.data.get("parts") is Dictionary:
		var p: Dictionary = s.data["parts"]
		var names := PackedStringArray()
		for key: String in ["head", "handle", "binding"]:
			var part: Dictionary = p.get(key, {})
			if not part.is_empty():
				var pd := registry.item(StringName(part["id"]))
				names.append("%s: %s" % [pd.display_name(locale) if pd else part["id"], data.material_name(StringName(part["material"]), locale).to_lower()])
		out.append("Части — " + "; ".join(names))
	if d.is_part() and s.data.has("material"):
		var m := data.material(StringName(s.data["material"]))
		if not m.is_empty():
			match String(m["category"]):
				"metal", "stone":
					out.append("Материал: уровень %d, скорость %.1f, острота %.1f, прочность ×%.1f" % [int(m["tier"]),
						float(m["speed"]), float(m["sharpness"]), float(m["toughness"])])
				_:
					out.append("Материал: прочность ×%.2f, гибкость ×%.2f" % [float(m["toughness"]), float(m["flexibility"])])
	if d.is_fuel():
		out.append("Топливо: %d °C, %.0f мин" % [roundi(float(d.fuel["heat"])), float(d.fuel["minutes"])])
	if not d.unlocks.is_empty():
		out.append("ПКМ — прочитать чертёж (%d рец.)" % d.unlocks.size())
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
	if s.data.has("cook"):
		out.append({ "under": "Недожарено — можно отравиться", "over": "Пережарено — меньше сытости" }.get(String(s.data["cook"]), ""))
	if s.count > 1:
		out.append("Вес: %.2f кг × %d = %.1f кг" % [d.weight, s.count, d.weight * s.count])
	else:
		out.append("Вес: %.2f кг" % d.weight)
	return out
