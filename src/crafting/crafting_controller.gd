class_name CraftingController
extends Node
## Ремесло игрока (этап 6): ручные рецепты, книга рецептов (открытие по увиденным
## предметам и чертежам), задания станций режима recipe, сборка, ремонт, разборка, ковка с
## мини-игрой. Окна строит Game; здесь — проверки и действия.

## Короткое сообщение игроку.
signal message(text: String)
## Открылись новые рецепты.
signal recipes_opened(ids: Array[StringName])
## Нужна мини-игра ковки: окно вызывает finish_forge(...) с баллом.
signal forge_requested(pos: Vector3i, recipe: StringName, material: StringName)

var world: World
var player: Player
var data: CraftingData
var book: RecipeBook
var stations: StationSystem
## Мини-игры включены (настройка «Мини-игры ремесла» = Вкл.).
var minigames := true

var _note_pending := false


func setup(p_world: World, p_player: Player, p_stations: StationSystem) -> void:
	world = p_world
	player = p_player
	stations = p_stations
	data = CraftingData.shared(world.registry)
	book = RecipeBook.new(data)
	player.inventory.changed.connect(_on_inventory_changed)


func _on_inventory_changed() -> void:
	if not _note_pending:
		_note_pending = true
		_note_inventory.call_deferred()


func _note_inventory() -> void:
	_note_pending = false
	var opened := book.note_inventory(player.inventory)
	if not opened.is_empty():
		_announce(opened)


func _announce(ids: Array[StringName]) -> void:
	recipes_opened.emit(ids)
	var names := PackedStringArray()
	for id in ids.slice(0, 3):
		names.append(data.recipe_name(data.recipe(id)))
	var more := " и ещё %d" % (ids.size() - 3) if ids.size() > 3 else ""
	message.emit("Новые рецепты: %s%s" % [", ".join(names), more])
	_play_ui("crafting/recipe")


func _play_ui(key: String) -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio != null:
		audio.play_ui(key)


# --- руки -------------------------------------------------------------------------------------

## Известные ручные рецепты.
func hand_recipes() -> Array:
	var out := []
	for r: Dictionary in data.recipes_for(&"hand"):
		if book.is_known(StringName(r["id"])):
			out.append(r)
	return out


func craft_hand(r: Dictionary) -> bool:
	var res := Crafting.craft_hand(data, r, player.inventory)
	if not res["ok"]:
		message.emit(String(res["reason"]).capitalize())
		return false
	for s: ItemStack in res["outputs"]:
		world.items_dropped.emit(player.body.x, player.body.y + 1.0, player.body.z, [s])
	_play_ui("crafting/craft")
	return true


## ПКМ с чертежом в руке: прочитать (рецепты открываются, чертёж расходуется).
func read_blueprint() -> bool:
	var d := player.inventory.held_def()
	if d == null or d.unlocks.is_empty():
		return false
	var opened := book.use_blueprint(d.id)
	if opened.is_empty():
		message.emit("Эти рецепты уже известны")
		return true
	player.inventory.consume_held()
	_announce(opened)
	return true


func _process(_delta: float) -> void:
	if player == null or not player.input_allowed() or not Input.is_action_just_pressed(&"use"):
		return
	var d := player.inventory.held_def()
	if d != null and not d.unlocks.is_empty() and not player.interaction.target.get("hit", false):
		read_blueprint()


# --- станции режима recipe ----------------------------------------------------------------------

## Известные рецепты станции (кроме служебных — сборка, ремонт, разборка показываются отдельно).
func station_recipes(st: Station) -> Array:
	var out := []
	for r: Dictionary in data.recipes_for(st.kind):
		var op := String(r.get("op", "craft"))
		if op in ["assemble", "repair", "salvage"] or not book.is_known(StringName(r["id"])):
			continue
		if int(r.get("min_tier", 0)) > st.tier:
			continue
		out.append(r)
	return out


## Сколько раз хватает материалов у игрока.
func available(r: Dictionary) -> int:
	return Ingredients.times_available(data, r.get("inputs", []), player.inventory.storages(), 99)


## Почему не начать (пусто — можно).
func recipe_blocker(st: Station, p: Vector3i, r: Dictionary, material: StringName = &"") -> String:
	if st.queue.size() >= Station.QUEUE_MAX:
		return "Очередь заполнена"
	if available(r) <= 0:
		return "Не хватает материалов"
	if String(r.get("op", "")) == "forge_part":
		var m := material if material != &"" else _forge_material(r)
		var mat := data.material(m)
		if mat.is_empty():
			return "Нет слитков одного металла"
		if int(mat.get("tier", 0)) <= 0:
			return "Из %s инструменты не куют" % String(mat["name"]["ru"]).to_lower()
		if int(mat.get("tier", 0)) > st.tier:
			return "Наковальня слишком слабая для металла «%s»" % String(mat["name"]["ru"]).to_lower()
		if not stations.heat_near(p, 4, forge_heat(m)):
			return "Нужен горящий горн или печь рядом (от %d °C)" % roundi(forge_heat(m))
	return ""


## Жар, при котором металл куётся (60 % температуры плавления).
func forge_heat(material: StringName) -> float:
	return float(data.material(material).get("melt", 1000.0)) * 0.6


func _forge_material(r: Dictionary) -> StringName:
	var n := int((r.get("inputs", []) as Array)[0].get("count", 1)) if not (r.get("inputs", []) as Array).is_empty() else 1
	var opts := Ingredients.ingot_materials(data, player.inventory.storages(), n)
	return StringName(opts[0][0]) if not opts.is_empty() else &""


## Металлы, из которых можно выковать часть (хватает слитков).
func forge_materials(r: Dictionary) -> Array:
	var n := int((r.get("inputs", []) as Array)[0].get("count", 1))
	return Ingredients.ingot_materials(data, player.inventory.storages(), n)


## Начать рецепт count раз. Ковка с мини-игрой — через forge_requested.
func start_recipe(st: Station, p: Vector3i, r: Dictionary, count: int = 1, material: StringName = &"") -> bool:
	if String(r.get("op", "")) == "forge_part":
		var m := material if material != &"" else _forge_material(r)
		var why := recipe_blocker(st, p, r, m)
		if why != "":
			message.emit(why)
			return false
		if minigames:
			forge_requested.emit(p, StringName(r["id"]), m)
			return true
		return finish_forge(st, r, m, CraftingData.AUTO_SCORE)
	var done := 0
	for i in count:
		if recipe_blocker(st, p, r) != "":
			break
		var consumed := Ingredients.take(data, r.get("inputs", []), player.inventory.storages())
		if consumed.is_empty() and not (r.get("inputs", []) as Array).is_empty():
			break
		st.enqueue(r, consumed, -1.0)
		done += 1
	if done == 0:
		message.emit(recipe_blocker(st, p, r))
		return false
	stations.flush(_pos_of(st))
	_play_ui("crafting/craft")
	return true


## Итог мини-игры ковки (или авто): списать слитки и поставить задание.
func finish_forge(st: Station, r: Dictionary, material: StringName, score: float) -> bool:
	var consumed := Ingredients.take(data, r.get("inputs", []), player.inventory.storages(), material)
	if consumed.is_empty():
		message.emit("Слитки кончились")
		return false
	st.enqueue(r, consumed, score)
	stations.flush(_pos_of(st))
	return true


func _pos_of(st: Station) -> Vector3i:
	for p: Vector3i in stations.stations:
		if stations.stations[p] == st:
			return p
	return Vector3i.ZERO


# --- верстак: сборка, ремонт, разборка -----------------------------------------------------------

## Какой инструмент соберётся из частей во входах верстака (по навершию) — рецепт или пусто.
func assembly_recipe(st: Station) -> Dictionary:
	var head := st.inputs.get_stack(0)
	if head == null:
		return {}
	for r: Dictionary in data.recipes_for(st.kind):
		if String(r.get("op", "")) != "assemble":
			continue
		var t: Dictionary = data.tool_types.get(StringName(r["tool_type"]), {})
		if String(t.get("head", "")) == String(head.id):
			return r if book.is_known(StringName(r["id"])) else {}
	return {}


## Предпросмотр свойств сборки или пусто.
func assembly_preview(st: Station) -> Dictionary:
	var r := assembly_recipe(st)
	if r.is_empty():
		return {}
	var why := ToolAssembly.check(data, StringName(r["tool_type"]), st.inputs.get_stack(0), st.inputs.get_stack(1),
		st.inputs.get_stack(2))
	if why != "":
		return { "error": why }
	var parts := {}
	var keys := ["head", "handle", "binding"]
	for i in 3:
		parts[keys[i]] = ToolAssembly.part_info(st.inputs.get_stack(i), data)
	var stats := ToolAssembly.compute(data, StringName(r["tool_type"]), parts["head"], parts["handle"], parts["binding"])
	stats["quality"] = ToolAssembly.quality_of(data, parts["head"], parts["handle"], parts["binding"],
		float(st.def.get("quality_bonus", 0.0)))
	stats["name"] = data.recipe_name(r)
	return stats


func assemble(st: Station) -> bool:
	var r := assembly_recipe(st)
	if r.is_empty():
		message.emit("Положите навершие, рукоять и обмотку (рецепт сборки должен быть известен)")
		return false
	var why := st.start_assembly(r)
	if why != "":
		message.emit(why.capitalize())
		return false
	stations.flush(_pos_of(st))
	_play_ui("crafting/craft")
	return true


func _service_recipe(st: Station, op: String) -> Dictionary:
	for r: Dictionary in data.recipes_for(st.kind):
		if String(r.get("op", "")) == op:
			return r
	return {}


## Починить инструмент из первой ячейки входа материалом из инвентаря игрока.
func repair(st: Station) -> bool:
	var tool := st.inputs.get_stack(0)
	var r := _service_recipe(st, "repair")
	if tool == null or r.is_empty() or not tool.data.has("parts"):
		message.emit("Положите инструмент из частей в первую ячейку")
		return false
	var units := Crafting.repair_units(data, tool)
	if units <= 0:
		message.emit("Чинить нечего")
		return false
	var mat := data.material(Crafting.repair_material(data, tool))
	if st.kind == &"anvil" and String(mat.get("category", "")) != "metal":
		message.emit("Каменные инструменты чинят на верстаке")
		return false
	var invs: Array = player.inventory.storages()
	while units > 0 and not Ingredients.can_take(data, Crafting.repair_inputs(data, tool, units), invs):
		units -= 1
	if units <= 0:
		message.emit("Нужен материал навершия: %s" % String(mat.get("name", {}).get("ru", "?")).to_lower())
		return false
	var consumed := Ingredients.take(data, Crafting.repair_inputs(data, tool, units), invs)
	st.start_repair(r, consumed, units)
	stations.flush(_pos_of(st))
	return true


func salvage(st: Station) -> bool:
	var r := _service_recipe(st, "salvage")
	if r.is_empty():
		return false
	var why := st.start_salvage(r)
	if why != "":
		message.emit(why.capitalize())
		return false
	stations.flush(_pos_of(st))
	return true


func to_dict() -> Dictionary:
	return book.to_dict()


func from_dict(d: Dictionary) -> void:
	book.from_dict(d)
