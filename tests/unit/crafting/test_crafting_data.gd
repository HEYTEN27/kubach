extends GutTest
## Согласованность данных ремесла: все ссылки рецептов, материалов, станций и моделей.

var data: CraftingData


func before_all() -> void:
	data = CraftingData.new(Registry)


func test_counts() -> void:
	assert_gte(data.recipes.size(), 150, "рецептов много")
	assert_eq(data.qualities.size(), 5, "5 уровней качества")
	assert_gte(data.tool_types.size(), 7)
	assert_true(Registry.block_count() >= 260)


func test_recipe_refs() -> void:
	for id: StringName in data.recipes:
		var r: Dictionary = data.recipes[id]
		assert_true(data.stations.has(StringName(r["station"])), "%s: станция" % id)
		for inp: Dictionary in r["inputs"]:
			var iid := String(inp.get("id", ""))
			if iid != "":
				assert_not_null(Registry.item(StringName(iid)), "%s: вход %s" % [id, iid])
			else:
				assert_true(_tag_used(String(inp["tag"])), "%s: тег %s есть у предметов" % [id, inp["tag"]])
		var oid := String(r.get("output", {}).get("id", ""))
		if oid != "":
			assert_not_null(Registry.item(StringName(oid)), "%s: выход %s" % [id, oid])
		for e: Dictionary in r["extra"]:
			assert_not_null(Registry.item(StringName(e["id"])), "%s: побочный %s" % [id, e["id"]])
		var tt := String(r.get("tool_type", ""))
		if String(r["op"]) == "assemble":
			assert_true(data.tool_types.has(StringName(tt)), "%s: инструмент %s" % [id, tt])
		if String(r["op"]) == "alloy":
			var found := false
			for a in data.alloys:
				found = found or String(a["id"]) == tt
			assert_true(found, "%s: сплав %s" % [id, tt])
		if String(r["op"]) == "forge_part":
			assert_true(data.parts.has(StringName(oid)), "%s: выход — часть" % id)


func _tag_used(tag: String) -> bool:
	if tag == "ingot":
		return true
	for d in Registry.items():
		if d.tags.has(tag):
			return true
	return false


func test_materials() -> void:
	for mid: StringName in data.materials:
		for src: String in data.materials[mid]["sources"]:
			assert_not_null(Registry.item(StringName(src)), "%s: источник %s" % [mid, src])
	assert_eq(data.material_of(ItemStack.make(&"steel_ingot")), &"steel")
	assert_eq(data.material_of(ItemStack.make(&"oak_planks")), &"oak")
	assert_eq(data.material_of(ItemStack.make(&"granite")), &"stone", "порода по тегу rock")
	assert_eq(data.material_of(ItemStack.make(&"stick")), &"wood")
	for a in data.alloys:
		for c: Dictionary in a["components"]:
			for it: String in c["items"]:
				assert_not_null(Registry.item(StringName(it)), "%s: %s" % [a["id"], it])


func test_stations_and_models() -> void:
	var kinds := {}
	for b in range(1, Registry.block_count()):
		var def := Registry.block_by_num(b)
		if def.is_station():
			kinds[def.station_kind] = true
			assert_true(data.stations.has(def.station_kind), "%s: вид станции" % def.id)
			assert_true(def.has_model(), "%s: у станции модель" % def.id)
			assert_not_null(Registry.item(def.id), "%s: станцию можно поставить" % def.id)
		for box: Dictionary in def.model:
			assert_gte(Registry.block_num(box["tex"]), 0, "%s: текстура модели %s" % [def.id, box["tex"]])
	for sid: StringName in data.stations:
		if sid != &"hand":
			assert_true(kinds.has(sid), "есть блок станции %s" % sid)
	# Каждую станцию можно сделать.
	for b in range(1, Registry.block_count()):
		var def := Registry.block_by_num(b)
		if def.is_station() and def.id != &"campfire":
			var made := false
			for id: StringName in data.recipes:
				made = made or String(data.recipes[id].get("output", {}).get("id", "")) == String(def.id)
			assert_true(made, "%s: есть рецепт" % def.id)


func test_quality_levels() -> void:
	assert_eq(data.quality_level(0.0), 0)
	assert_eq(data.quality_level(0.5), 1)
	assert_eq(data.quality_level(0.6), 2)
	assert_eq(data.quality_level(0.8), 3)
	assert_eq(data.quality_level(0.95), 4)
	assert_eq(data.quality_name(4), "Шедевр")
	assert_gt(data.quality_mult(4), data.quality_mult(0))
	# Обычные входы в авто-режиме — «обычное», хорошие входы и игра — выше.
	assert_eq(data.quality_level(CraftingData.combine_score(0.4, CraftingData.AUTO_SCORE, 0.1)), 1)
	assert_gte(data.quality_level(CraftingData.combine_score(0.85, 1.0, 0.1)), 4)


func test_fuel_and_items() -> void:
	assert_gt(float(data.fuel_of(&"charcoal").get("heat", 0)), 1000.0)
	assert_false(data.fuel_of(&"oak_log").is_empty(), "бревно горит")
	assert_true(data.fuel_of(&"granite").is_empty())
	var head := Registry.item(&"pickaxe_head")
	assert_true(head.is_part())
	var pick := Registry.item(&"pickaxe")
	assert_true(pick.is_assembled() and pick.is_tool())
