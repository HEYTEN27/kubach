class_name ToolAssembly
extends RefCounted
## Инструмент из частей (раздел 5.1 ТЗ): навершие + рукоять + обмотка. Материал каждой части
## даёт свои свойства — уровень и скорость добычи и острота от навершия, прочность от всех
## трёх (твёрдость навершия, прочность и гибкость рукояти, хватка обмотки), вес по частям.
## Закалка добавляет прочность, заточка — скорость и урон, качество частей — множитель.
## Название — по материалу навершия: «Стальная кирка», «Кремнёвый нож».

const QUENCH_DURABILITY := 1.2
const SHARPEN_SPEED := 1.1
const SHARPEN_DAMAGE := 1.15
## Доли частей в итоговом качестве инструмента.
const W_HEAD := 0.6
const W_HANDLE := 0.25
const W_BINDING := 0.15


## Данные одной части стопки: { id, material, quality, quenched, sharpened }.
static func part_info(s: ItemStack, data: CraftingData) -> Dictionary:
	return {
		"id": String(s.id), "material": String(data.material_of(s)), "quality": int(s.data.get("quality", 1)),
		"quenched": bool(s.data.get("quenched", false)), "sharpened": bool(s.data.get("sharpened", false)),
	}


## Почему эти части нельзя собрать в инструмент type_id (пусто — можно).
## categories — разрешённые категории материала навершия (ручная сборка — только камень).
static func check(data: CraftingData, type_id: StringName, head: ItemStack, handle: ItemStack, binding: ItemStack,
		categories: Array = []) -> String:
	var t: Dictionary = data.tool_types.get(type_id, {})
	if t.is_empty():
		return "нет такого инструмента"
	if head == null or String(head.id) != String(t["head"]):
		return "нужно: %s" % data.registry.item(StringName(t["head"])).display_name()
	if handle == null or String(handle.id) != String(t["handle"]):
		return "нужно: %s" % data.registry.item(StringName(t["handle"])).display_name()
	if binding == null or String(binding.id) != String(t["binding"]):
		return "нужно: %s" % data.registry.item(StringName(t["binding"])).display_name()
	var hm := data.material(data.material_of(head))
	if hm.is_empty():
		return "у навершия нет материала"
	if not categories.is_empty() and not categories.has(String(hm["category"])):
		return "здесь не собрать: материал навершия — %s" % String(hm["name"]["ru"]).to_lower()
	return ""


## Свойства инструмента: { tier, speed, damage, durability, weight }.
static func compute(data: CraftingData, type_id: StringName, head: Dictionary, handle: Dictionary,
		binding: Dictionary) -> Dictionary:
	var t: Dictionary = data.tool_types[type_id]
	var hm := data.material(StringName(head["material"]))
	var wm := data.material(StringName(handle["material"]))
	var bm := data.material(StringName(binding["material"]))
	var qh := data.quality_mult(int(head.get("quality", 1)))
	var qw := data.quality_mult(int(handle.get("quality", 1)))
	var qb := data.quality_mult(int(binding.get("quality", 1)))
	var sharp: bool = head.get("sharpened", false)
	var speed := float(hm.get("speed", 1.0)) * float(t["speed"]) * sqrt(qh) * (SHARPEN_SPEED if sharp else 1.0)
	var damage := (float(t["damage"]) + float(hm.get("sharpness", 0.0)) * float(t["sharp_k"])) * qh \
			* (SHARPEN_DAMAGE if sharp else 1.0)
	var dur := float(t["durability"]) * float(hm.get("toughness", 1.0)) \
			* (0.6 + 0.4 * float(wm.get("toughness", 1.0)) * float(wm.get("flexibility", 1.0))) \
			* (0.75 + 0.25 * float(bm.get("toughness", 1.0)) * float(bm.get("flexibility", 1.0))) \
			* (qh * 0.7 + qw * 0.2 + qb * 0.1) * (QUENCH_DURABILITY if head.get("quenched", false) else 1.0)
	var weight := 0.0
	for pair: Array in [[head, t["head"]], [handle, t["handle"]], [binding, t["binding"]]]:
		var p: Dictionary = data.parts.get(StringName(pair[1]), {})
		var m := data.material(StringName((pair[0] as Dictionary)["material"]))
		weight += float(p.get("units", 1)) * float(p.get("weight", 1.0)) * float(m.get("weight", 0.5))
	return {
		"tier": int(hm.get("tier", 1)), "speed": snappedf(speed, 0.01), "damage": snappedf(damage, 0.1),
		"durability": maxi(1, roundi(dur)), "weight": snappedf(weight, 0.01),
	}


## Уровень качества инструмента по частям и бонусу станции.
static func quality_of(data: CraftingData, head: Dictionary, handle: Dictionary, binding: Dictionary,
		station_bonus: float) -> int:
	var sc := W_HEAD * data.quality_score(int(head.get("quality", 1))) \
			+ W_HANDLE * data.quality_score(int(handle.get("quality", 1))) \
			+ W_BINDING * data.quality_score(int(binding.get("quality", 1)))
	return data.quality_level(clampf(sc * 0.95 + station_bonus * 0.5, 0.0, 1.0))


## Собрать инструмент (части не трогает — их снимает вызывающий).
static func make(data: CraftingData, type_id: StringName, head: ItemStack, handle: ItemStack, binding: ItemStack,
		station_bonus: float = 0.0) -> ItemStack:
	var h := part_info(head, data)
	var w := part_info(handle, data)
	var b := part_info(binding, data)
	var stats := compute(data, type_id, h, w, b)
	var s := ItemStack.make(type_id, 1)
	s.data["parts"] = { "head": h, "handle": w, "binding": b }
	s.data["quality"] = quality_of(data, h, w, b, station_bonus)
	s.data["max_durability"] = stats["durability"]
	s.data["durability"] = stats["durability"]
	s.data["stats"] = { "tier": stats["tier"], "speed": stats["speed"], "damage": stats["damage"], "weight": stats["weight"] }
	return s


## Свойства инструмента в руке: у собранного — из данных, у готового (этап 4) — из определения.
## { type, tier, speed } или пусто.
static func tool_of(s: ItemStack, def: ItemDef) -> Dictionary:
	if def == null or not def.is_tool():
		return {}
	if def.is_assembled() and s != null and s.data.has("stats"):
		var st: Dictionary = s.data["stats"]
		return { "type": def.tool["type"], "tier": int(st.get("tier", 1)), "speed": float(st.get("speed", 1.0)) }
	return def.tool


static func damage_of(s: ItemStack, def: ItemDef) -> float:
	if def != null and def.is_assembled() and s != null and s.data.has("stats"):
		return float(s.data["stats"].get("damage", def.damage))
	return def.damage if def != null else 1.0


## Разобрать инструмент: части возвращаются; навершие и рукоять — если инструмент не изношен
## больше чем наполовину, обмотка всегда пропадает (её не размотать целой).
static func salvage(s: ItemStack, def: ItemDef) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	var parts: Dictionary = s.data.get("parts", {})
	if parts.is_empty():
		return out
	var worn := float(s.data.get("durability", 1)) / maxf(1.0, float(s.max_durability(def)))
	for key: String in ["head", "handle"]:
		var p: Dictionary = parts.get(key, {})
		if p.is_empty() or (key == "handle" and worn < 0.5):
			continue
		var ps := ItemStack.make(StringName(p["id"]), 1)
		ps.data["material"] = p["material"]
		ps.data["quality"] = maxi(0, int(p.get("quality", 1)) - (0 if worn >= 0.5 else 1))
		if p.get("quenched", false):
			ps.data["quenched"] = true
		out.append(ps)
	return out


## Название стопки с учётом ремесла: инструмент — по навершию, часть — с материалом и
## обработкой, крашеная ткань — с цветом. Остальное — обычное название.
static func display_name(s: ItemStack, def: ItemDef, data: CraftingData, locale: String = "ru") -> String:
	if def == null:
		return String(s.id)
	var base := def.display_name(locale)
	if def.is_assembled() and s.data.has("parts"):
		var t: Dictionary = data.tool_types.get(def.id, {})
		var head: Dictionary = s.data["parts"].get("head", {})
		var a := data.material_adj(StringName(head.get("material", "")), String(t.get("gender", "f")), locale)
		if locale == "ru":
			return a.capitalize() + " " + base.to_lower() if a != "" else base
		return "%s %s" % [a, base]
	if def.is_part() and s.data.has("material"):
		var extra := PackedStringArray([data.material_name(StringName(s.data["material"]), locale).to_lower()])
		if s.data.get("quenched", false):
			extra.append("закалено" if locale == "ru" else "quenched")
		if s.data.get("sharpened", false):
			extra.append("заточено" if locale == "ru" else "sharpened")
		return "%s (%s)" % [base, ", ".join(extra)]
	if s.data.has("color") and def.tags.has("cloth"):
		return "%s (%s)" % [base, color_name(String(s.data["color"]), data, locale)]
	return base


## Ближайшая краска по цвету — для названия крашеной ткани.
static func color_name(hex: String, data: CraftingData, locale: String = "ru") -> String:
	var c := Color.html(hex)
	var best := ""
	var best_d := INF
	for d in data.registry.items():
		if d.dye == "":
			continue
		var dc := Color.html(d.dye)
		var dist := Vector3(c.r - dc.r, c.g - dc.g, c.b - dc.b).length_squared()
		if dist < best_d:
			best_d = dist
			var n := d.display_name(locale)
			best = n.split(" ")[0].to_lower() if locale == "ru" else n.split(" ")[0].to_lower()
	return best if best != "" else hex
