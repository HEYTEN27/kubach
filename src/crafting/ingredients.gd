class_name Ingredients
extends RefCounted
## Поиск и списание входов рецепта из набора инвентарей (рюкзак игрока, слоты станции).
## Вход — { id, tag, count }; tag "ingot" особый: все слитки одного металла (материал
## результата ковки берётся из них). Списанное возвращается стопками — по ним считаются
## материал и качество результата.


## Сколько раз можно выполнить рецепт (0 — нельзя). Учитывает, что входы делят предметы.
static func times_available(data: CraftingData, inputs: Array, invs: Array, limit: int = 99) -> int:
	if inputs.is_empty():
		return limit
	var n := 0
	while n < limit and _can_take(data, inputs, invs, n + 1):
		n += 1
	return n


static func can_take(data: CraftingData, inputs: Array, invs: Array) -> bool:
	return _can_take(data, inputs, invs, 1)


static func _can_take(data: CraftingData, inputs: Array, invs: Array, times: int) -> bool:
	var used := {}   # "inv:slot" → занято штук
	for inp: Dictionary in inputs:
		var need := int(inp.get("count", 1)) * times
		if String(inp.get("tag", "")) == "ingot":
			if _best_ingot_group(data, invs, used, need).is_empty():
				return false
			continue
		for ii in invs.size():
			var inv: Inventory = invs[ii]
			for i in inv.size():
				if need <= 0:
					break
				var s := inv.get_stack(i)
				if not data.input_matches(inp, s):
					continue
				var key := "%d:%d" % [ii, i]
				var free := s.count - int(used.get(key, 0))
				var take := mini(free, need)
				if take > 0:
					used[key] = int(used.get(key, 0)) + take
					need -= take
		if need > 0:
			return false
	return true


## Слитки одного металла: [материал, список "inv:slot"] для металла, которого хватает, или пусто.
static func _best_ingot_group(data: CraftingData, invs: Array, used: Dictionary, need: int) -> Array:
	var groups := {}   # материал → количество
	for ii in invs.size():
		var inv: Inventory = invs[ii]
		for i in inv.size():
			var s := inv.get_stack(i)
			if s == null or not data.has_tag(s.id, "ingot"):
				continue
			var m := data.material_of(s)
			var free := s.count - int(used.get("%d:%d" % [ii, i], 0))
			groups[m] = int(groups.get(m, 0)) + free
	var best: StringName = &""
	for m: StringName in groups:
		if int(groups[m]) >= need and (best == &"" or int(groups[m]) > int(groups[best])):
			best = m
	if best == &"":
		return []
	var left := need
	for ii in invs.size():
		var inv: Inventory = invs[ii]
		for i in inv.size():
			var s := inv.get_stack(i)
			if left <= 0 or s == null or not data.has_tag(s.id, "ingot") or data.material_of(s) != best:
				continue
			var key := "%d:%d" % [ii, i]
			var take := mini(s.count - int(used.get(key, 0)), left)
			used[key] = int(used.get(key, 0)) + take
			left -= take
	return [best]


## Списать входы. prefer_material — для тега ingot взять именно этот металл (выбор игрока).
## Возвращает списанные стопки или пусто, если не хватило (тогда ничего не списано).
static func take(data: CraftingData, inputs: Array, invs: Array, prefer_material: StringName = &"") -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	if not can_take(data, inputs, invs):
		return out
	for inp: Dictionary in inputs:
		var need := int(inp.get("count", 1))
		var ingot := String(inp.get("tag", "")) == "ingot"
		var metal := prefer_material
		if ingot and (metal == &"" or count_material(data, invs, metal) < need):
			var g := _best_ingot_group(data, invs, {}, need)
			metal = g[0] if not g.is_empty() else &""
		for inv: Inventory in invs:
			for i in inv.size():
				if need <= 0:
					break
				var s := inv.get_stack(i)
				if s == null:
					continue
				if ingot:
					if not data.has_tag(s.id, "ingot") or data.material_of(s) != metal:
						continue
				elif not data.input_matches(inp, s):
					continue
				var n := mini(s.count, need)
				out.append(s.split(n))
				inv.set_stack(i, s if s.count > 0 else null)
				need -= n
	return out


## Сколько слитков металла material во всех инвентарях.
static func count_material(data: CraftingData, invs: Array, material: StringName) -> int:
	var n := 0
	for inv: Inventory in invs:
		for i in inv.size():
			var s := inv.get_stack(i)
			if s != null and data.has_tag(s.id, "ingot") and data.material_of(s) == material:
				n += s.count
	return n


## Металлы, из слитков которых хватает на n единиц: [[материал, штук], ...].
static func ingot_materials(data: CraftingData, invs: Array, n: int) -> Array:
	var counts := {}
	for inv: Inventory in invs:
		for i in inv.size():
			var s := inv.get_stack(i)
			if s != null and data.has_tag(s.id, "ingot"):
				var m := data.material_of(s)
				counts[m] = int(counts.get(m, 0)) + s.count
	var out := []
	for m: StringName in counts:
		if int(counts[m]) >= n:
			out.append([m, counts[m]])
	return out


## Средний балл качества списанных стопок (с учётом количества).
static func average_score(data: CraftingData, stacks: Array[ItemStack]) -> float:
	var total := 0.0
	var n := 0
	for s in stacks:
		total += data.stack_score(s) * s.count
		n += s.count
	return total / n if n > 0 else CraftingData.RAW_SCORE


## Материал результата: первый вход с материалом (слитки, доски, бечёвка, кремень).
static func material_from(data: CraftingData, stacks: Array[ItemStack]) -> StringName:
	for s in stacks:
		var m := data.material_of(s)
		if m != &"":
			return m
	return &""


## Вернуть стопки обратно в инвентари (отмена); что не влезло — остаётся в массиве.
static func give_back(stacks: Array[ItemStack], invs: Array) -> Array[ItemStack]:
	var left: Array[ItemStack] = []
	for s in stacks:
		var rest := s.count
		for inv: Inventory in invs:
			if rest <= 0:
				break
			var part := s.copy()
			part.count = rest
			rest = inv.add(part)
		if rest > 0:
			var r := s.copy()
			r.count = rest
			left.append(r)
	return left
