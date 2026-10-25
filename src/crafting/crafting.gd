class_name Crafting
extends RefCounted
## Результат рецепта (раздел 5 ТЗ) по списанным входам, баллу мастерства и параметрам:
## обычный рецепт, ковка части (материал — из слитков/досок/кремня), сплав, сборка
## инструмента, закалка, заточка, крашение, готовка (зона прожарки), ремонт, разборка.
## Плюс ручное ремесло — сразу из инвентаря игрока.

## Закалка в воде: шанс трещины (качество −1). В масле (жир) — без риска.
const WATER_CRACK_CHANCE := 0.2
## Ремонт: одна единица материала навершия возвращает такую долю прочности.
const REPAIR_PER_UNIT := 0.35


## Балл результата рецепта.
static func score(data: CraftingData, consumed: Array[ItemStack], game_score: float, station_bonus: float) -> float:
	return CraftingData.combine_score(Ingredients.average_score(data, consumed), game_score, station_bonus)


## Выход рецепта. params: material (ковка), alloy + factor (сплав), zone (готовка),
## parts (сборка), medium (закалка: water/oil), rng.
static func outputs(data: CraftingData, r: Dictionary, consumed: Array[ItemStack], sc: float,
		params: Dictionary = {}) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	var rng: RandomNumberGenerator = params.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var o: Dictionary = r.get("output", {})
	var oid := StringName(o.get("id", ""))
	var n := int(o.get("count", 1))
	match String(r.get("op", "craft")):
		"craft":
			var s := _stack(data, oid, n, sc)
			if s != null:
				out.append(s)
		"forge_part":
			var s := _stack(data, oid, n, sc)
			if s != null:
				var m: StringName = params.get("material", Ingredients.material_from(data, consumed))
				s.data["material"] = String(m)
				s.data["quality"] = data.quality_level(sc)
				out.append(s)
		"alloy":
			var a: Dictionary = params.get("alloy", {})
			var units := int(params.get("units", n))
			var s := _stack(data, StringName(a.get("result", oid)), units, sc * (0.4 + 0.6 * float(params.get("factor", 1.0))))
			if s != null:
				out.append(s)
		"assemble":
			var p: Dictionary = params.get("parts", {})
			if p.size() == 3:
				out.append(ToolAssembly.make(data, StringName(r["tool_type"]), p["head"], p["handle"], p["binding"],
					float(params.get("station_bonus", 0.0))))
		"quench":
			for s in consumed:
				if s.data.has("material") and not data.has_tag(s.id, "quench_oil"):
					var q := s.copy()
					q.data["quenched"] = true
					if String(params.get("medium", "water")) == "water" and rng.randf() < WATER_CRACK_CHANCE:
						q.data["quality"] = maxi(0, int(q.data.get("quality", 1)) - 1)
					out.append(q)
		"sharpen":
			for s in consumed:
				var q := s.copy()
				q.data["sharpened"] = true
				out.append(q)
		"dye":
			var cloth: ItemStack = null
			var color := ""
			for s in consumed:
				var d := data.registry.item(s.id)
				if d != null and d.dye != "":
					color = d.dye
				elif d != null and d.tags.has("cloth"):
					cloth = s
			if cloth != null and color != "":
				var q := cloth.copy()
				q.data["color"] = color
				out.append(q)
		"cook":
			var zone := String(params.get("zone", "perfect"))
			if zone == "burnt":
				var burnt := String(r.get("cook", {}).get("burnt", "burnt_food"))
				var b := _stack(data, StringName(burnt), n, sc)
				if b != null:
					out.append(b)
			else:
				var s := _stack(data, oid, n, sc)
				if s != null:
					if zone != "perfect":
						s.data["cook"] = zone
					out.append(s)
		"repair":
			var tool: ItemStack = params.get("tool", null)
			if tool != null:
				out.append(repaired(data, tool, int(params.get("units", 1))))
		"salvage":
			for s in consumed:
				out.append_array(ToolAssembly.salvage(s, data.registry.item(s.id)))
	for e: Dictionary in r.get("extra", []):
		if rng.randf() < float(e.get("chance", 1.0)):
			var x := _stack(data, StringName(e["id"]), int(e.get("count", 1)), sc)
			if x != null:
				out.append(x)
	return out


static func _stack(data: CraftingData, id: StringName, n: int, sc: float) -> ItemStack:
	var d := data.registry.item(id)
	if d == null or n <= 0:
		return null
	var s := ItemStack.create(d, 1)
	s.count = n
	if d.quality and not d.is_assembled():
		s.data["quality"] = data.quality_level(sc)
	return s


# --- ремонт -----------------------------------------------------------------------------------

## Чем чинить инструмент: материал навершия (слиток, кремень, камень). Пусто — нечем.
static func repair_material(data: CraftingData, tool: ItemStack) -> StringName:
	var head: Dictionary = tool.data.get("parts", {}).get("head", {})
	return StringName(head.get("material", ""))


## Сколько единиц материала нужно, чтобы починить полностью.
static func repair_units(data: CraftingData, tool: ItemStack) -> int:
	var d := data.registry.item(tool.id)
	var mx := float(tool.max_durability(d))
	var miss := 1.0 - float(tool.data.get("durability", mx)) / maxf(1.0, mx)
	return ceili(miss / REPAIR_PER_UNIT - 0.0001)


## Починенная копия: каждая единица — +35 % прочности; каждый ремонт чуть снижает наибольшую
## прочность (−5 %), чтобы вечный инструмент не получался.
static func repaired(data: CraftingData, tool: ItemStack, units: int) -> ItemStack:
	var d := data.registry.item(tool.id)
	var s := tool.copy()
	var mx := maxi(1, roundi(s.max_durability(d) * 0.95))
	s.data["max_durability"] = mx
	var cur := int(s.data.get("durability", mx))
	s.data["durability"] = mini(mx, cur + roundi(mx * REPAIR_PER_UNIT * units))
	return s


## Входы ремонта: предметы материала навершия (по источникам материала).
static func repair_inputs(data: CraftingData, tool: ItemStack, units: int) -> Array:
	var m := repair_material(data, tool)
	var mat := data.material(m)
	if mat.is_empty() or units <= 0:
		return []
	var srcs: Array = mat.get("sources", [])
	if not srcs.is_empty():
		return [{ "id": srcs[0], "count": units }]
	var tags: Array = mat.get("source_tags", [])
	return [{ "tag": tags[0], "count": units }] if not tags.is_empty() else []


# --- ручное ремесло -----------------------------------------------------------------------------

## Есть ли нужный инструмент (нож, топор) в инвентаре. Возвращает [инвентарь, ячейка] или [].
static func find_tool(data: CraftingData, inv: PlayerInventory, tool_type: String) -> Array:
	for st: Inventory in inv.storages():
		for i in st.size():
			var s := st.get_stack(i)
			if s == null:
				continue
			var d := data.registry.item(s.id)
			var t := ToolAssembly.tool_of(s, d)
			if not t.is_empty() and String(t["type"]) == tool_type:
				return [st, i]
	return []


## Части для сборки из инвентаря: { head, handle, binding } (ссылки на стопки) или пусто.
static func find_parts(data: CraftingData, invs: Array, type_id: StringName, categories: Array) -> Dictionary:
	var t: Dictionary = data.tool_types.get(type_id, {})
	if t.is_empty():
		return {}
	var found := {}
	for slot: String in ["head", "handle", "binding"]:
		var want := StringName(t[slot])
		var best: ItemStack = null
		for inv: Inventory in invs:
			for i in inv.size():
				var s := inv.get_stack(i)
				if s == null or s.id != want:
					continue
				if slot == "head" and not categories.is_empty():
					var m := data.material(data.material_of(s))
					if m.is_empty() or not categories.has(String(m["category"])):
						continue
				if best == null or int(s.data.get("quality", 1)) > int(best.data.get("quality", 1)):
					best = s
		if best == null:
			return {}
		found[slot] = best
	return found


## Почему рецепт нельзя сделать руками сейчас (пусто — можно).
static func hand_blocker(data: CraftingData, r: Dictionary, inv: PlayerInventory) -> String:
	var invs: Array = inv.storages()
	if String(r.get("needs_tool", "none")) != "none" and find_tool(data, inv, String(r["needs_tool"])).is_empty():
		return "нужен инструмент: %s" % ItemTooltip.TOOLS.get(StringName(r["needs_tool"]), r["needs_tool"])
	if String(r.get("op", "")) == "assemble":
		if find_parts(data, invs, StringName(r["tool_type"]), r.get("categories", [])).is_empty():
			return "нет частей"
		return ""
	if not Ingredients.can_take(data, r.get("inputs", []), invs):
		return "не хватает материалов"
	return ""


## Сделать рецепт руками. Возвращает { ok, reason, outputs (не влезшее — выбросить) }.
static func craft_hand(data: CraftingData, r: Dictionary, inv: PlayerInventory) -> Dictionary:
	var why := hand_blocker(data, r, inv)
	if why != "":
		return { "ok": false, "reason": why, "outputs": [] }
	var invs: Array = inv.storages()
	var res: Array[ItemStack] = []
	if String(r.get("op", "")) == "assemble":
		var p := find_parts(data, invs, StringName(r["tool_type"]), r.get("categories", []))
		var taken := {}
		for slot: String in p:
			var s: ItemStack = p[slot]
			taken[slot] = s.split(1)
			_cleanup(invs, s)
		res = outputs(data, r, [], 0.0, { "parts": taken, "station_bonus": 0.0 })
	else:
		var consumed := Ingredients.take(data, r.get("inputs", []), invs)
		var sc := score(data, consumed, CraftingData.PLAIN_SCORE, 0.0)
		res = outputs(data, r, consumed, sc)
	if String(r.get("needs_tool", "none")) != "none":
		var at := find_tool(data, inv, String(r["needs_tool"]))
		if not at.is_empty():
			wear(at[0], at[1], 1)
	var left: Array[ItemStack] = []
	for s in res:
		if inv.add(s) > 0:
			left.append(s)
	return { "ok": true, "reason": "", "outputs": left }


## Износ стопки в ячейке; сломалась — пропадает.
static func wear(inv: Inventory, i: int, amount: int) -> bool:
	var s := inv.get_stack(i)
	if s == null or not s.data.has("durability"):
		return false
	s.data["durability"] = int(s.data["durability"]) - amount
	if int(s.data["durability"]) <= 0:
		inv.set_stack(i, null)
		return true
	inv.set_stack(i, s)
	return false


## Убрать опустевшие стопки (после split) из инвентарей.
static func _cleanup(invs: Array, s: ItemStack) -> void:
	if s.count > 0:
		for inv: Inventory in invs:
			inv.changed.emit()
		return
	for inv: Inventory in invs:
		for i in inv.size():
			if inv.get_stack(i) == s:
				inv.set_stack(i, null)
				return
