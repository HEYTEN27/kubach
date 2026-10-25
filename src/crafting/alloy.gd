class_name Alloy
extends RefCounted
## Сплавы по пропорциям (раздел 5.2 ТЗ): бронза = медь 88 % + олово 12 %. Каждая единица
## входа (слиток или концентрат) — единица металла. Чем дальше доли от нужных, тем ниже
## качество: на каждые tolerance отклонения множитель балла падает на треть.


## Разбор входов под сплав: { valid, units, shares {материал: доля}, deviation, factor }.
## valid — есть все компоненты и нет посторонних предметов.
static func analyze(alloy: Dictionary, stacks: Array) -> Dictionary:
	var units := {}
	var total := 0
	var foreign := false
	for s: ItemStack in stacks:
		if s == null:
			continue
		var comp := component_of(alloy, s.id)
		if comp == "":
			foreign = true
			continue
		units[comp] = int(units.get(comp, 0)) + s.count
		total += s.count
	var shares := {}
	var dev := 0.0
	var all_present := true
	for c: Dictionary in alloy["components"]:
		var m := String(c["material"])
		var share := float(units.get(m, 0)) / total if total > 0 else 0.0
		shares[m] = share
		dev = maxf(dev, absf(share - float(c["share"])))
		if int(units.get(m, 0)) == 0:
			all_present = false
	var tol := float(alloy.get("tolerance", 0.04))
	return {
		"valid": all_present and not foreign and total > 0, "units": total, "shares": shares,
		"deviation": dev, "factor": clampf(1.0 - dev / (tol * 3.0), 0.0, 1.0),
	}


## Какой компонент сплава даёт предмет (материал) или пусто.
static func component_of(alloy: Dictionary, item_id: StringName) -> String:
	for c: Dictionary in alloy["components"]:
		if (c.get("items", []) as Array).has(String(item_id)):
			return String(c["material"])
	return ""


## Сплав, который получится из этих стопок (все компоненты есть, чужих нет), или пусто.
static func find(data: CraftingData, stacks: Array) -> Dictionary:
	for a in data.alloys:
		if analyze(a, stacks)["valid"]:
			return a
	return {}


## Сколько единиц каждого компонента нужно на n единиц сплава (для подсказки игроку).
static func recipe_for(alloy: Dictionary, n: int) -> Dictionary:
	var out := {}
	for c: Dictionary in alloy["components"]:
		out[String(c["material"])] = float(c["share"]) * n
	return out
