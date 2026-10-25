class_name RecipeBook
extends RefCounted
## Книга рецептов (раздел 5.5 ТЗ). Рецепт открывается:
## - default — известен сразу (простейшее: палки, бечёвка, кремнёвые инструменты, верстак);
## - ingredients — когда игрок впервые увидел (подобрал, сделал) все его входы;
## - blueprint — только чертежом (ПКМ с чертежом в руке). Позже — торговцы, квесты, навыки.
## Хранит известные рецепты и увиденные предметы; сохраняется в world.json игрока.

var data: CraftingData
var known := {}   # StringName рецепта → true
var seen := {}    # StringName предмета → true


func _init(p_data: CraftingData) -> void:
	data = p_data
	for id: StringName in data.recipes:
		if String(data.recipes[id].get("unlock", "ingredients")) == "default":
			known[id] = true


func is_known(id: StringName) -> bool:
	return known.has(id)


## Отметить увиденные предметы; возвращает новые открытые рецепты.
func note_items(ids: Array) -> Array[StringName]:
	var fresh := false
	for i in ids:
		var id := StringName(i)
		if not seen.has(id):
			seen[id] = true
			fresh = true
	var opened: Array[StringName] = []
	if not fresh:
		return opened
	for id: StringName in data.recipes:
		if known.has(id):
			continue
		var r: Dictionary = data.recipes[id]
		if String(r.get("unlock", "ingredients")) != "ingredients":
			continue
		if _inputs_seen(r):
			known[id] = true
			opened.append(id)
	return opened


func _inputs_seen(r: Dictionary) -> bool:
	var ins: Array = r.get("inputs", [])
	if ins.is_empty():
		# Сборка/обработка без явных входов — по выходу или виду инструмента.
		var t := String(r.get("tool_type", ""))
		return t != "" and seen.has(StringName(data.tool_types.get(StringName(t), {}).get("head", "")))
	for inp: Dictionary in ins:
		var iid := String(inp.get("id", ""))
		if iid != "":
			if not seen.has(StringName(iid)):
				return false
		elif not _tag_seen(String(inp.get("tag", ""))):
			return false
	return true


func _tag_seen(tag: String) -> bool:
	for id: StringName in seen:
		if data.has_tag(id, tag):
			return true
	return false


## Прочитать чертёж: открывает его рецепты. Возвращает новые.
func use_blueprint(item_id: StringName) -> Array[StringName]:
	var opened: Array[StringName] = []
	var d := data.registry.item(item_id)
	if d == null:
		return opened
	for rid in d.unlocks:
		var id := StringName(rid)
		if data.recipes.has(id) and not known.has(id):
			known[id] = true
			opened.append(id)
	return opened


## Отметить всё содержимое инвентаря игрока как увиденное.
func note_inventory(inv: PlayerInventory) -> Array[StringName]:
	var ids := []
	for st: Inventory in inv.storages() + [inv.equipment]:
		for i in st.size():
			var s := st.get_stack(i)
			if s != null:
				ids.append(s.id)
	return note_items(ids)


## Сколько рецептов известно и всего (для экрана книги).
func counts() -> Vector2i:
	return Vector2i(known.size(), data.recipes.size())


func to_dict() -> Dictionary:
	return { "known": known.keys().map(func(k: StringName) -> String: return String(k)),
		"seen": seen.keys().map(func(k: StringName) -> String: return String(k)) }


func from_dict(d: Dictionary) -> void:
	for k in d.get("known", []):
		if data.recipes.has(StringName(k)):
			known[StringName(k)] = true
	for k in d.get("seen", []):
		seen[StringName(k)] = true
