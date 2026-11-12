extends GutTest
## Кухня (этап 9): 80+ рецептов, одно сырьё — разные блюда разными способами, котёл с водой
## возвращает ведро, разнообразие еды, баффы от блюд, качество блюда.

var data: CraftingData


func before_all() -> void:
	data = CraftingData.shared(Registry)


func test_eighty_plus_recipes() -> void:
	var kitchen := 0
	for id: StringName in Registry.get_entries("recipes").map(func(e: Dictionary) -> StringName: return StringName(e["id"])):
		var r := data.recipe(id)
		var out := Registry.item(StringName(r["output"]["id"]))
		if out != null and (out.is_food() or out.tags.has("ingredient")):
			kitchen += 1
	assert_gte(kitchen, 80, "не меньше 80 рецептов еды")


func test_same_raw_different_methods() -> void:
	var outs := {}
	for e: Dictionary in Registry.get_entries("recipes"):
		for inp: Dictionary in e["inputs"]:
			if String(inp.get("id", "")) == "venison":
				outs[String(e["output"]["id"])] = String(e["station"])
	assert_gte(outs.size(), 3, "оленина: вертел, коптильня, сушилка")
	var roast := Registry.item(&"roast_venison").food
	var jerky := Registry.item(&"venison_jerky").food
	assert_gt(float(jerky["spoil_days"]), float(roast["spoil_days"]) * 10.0, "вяленая хранится много дольше жареной")
	assert_ne(roast.get("effects", []), jerky.get("effects", []), "и эффекты разные")


func test_cauldron_soup_returns_bucket() -> void:
	var st := Station.new(data, &"cauldron")
	st.auto = true
	st.fuel.set_stack(0, ItemStack.make(&"charcoal", 8))
	var r := data.recipe(&"cauldron_shchi")
	var consumed: Array[ItemStack] = [ItemStack.make(&"cabbage", 1), ItemStack.make(&"potato", 1), ItemStack.make(&"carrot", 1),
		ItemStack.make(&"beef", 1), ItemStack.make(&"wooden_bucket_water", 1, { "amount": 8, "water_kind": "fresh" }),
		ItemStack.make(&"clay_bowl", 2)]
	assert_true(st.enqueue(r, consumed, -1.0))
	st.advance(200.0)
	var ids := []
	for i in st.outputs.size():
		var s := st.outputs.get_stack(i)
		if s != null:
			ids.append(s.id)
	assert_has(ids, &"shchi", "щи сварились")
	assert_has(ids, &"wooden_bucket", "пустое ведро вернулось")


func test_variety_and_quality() -> void:
	var v := PlayerVitals.from_registry(Registry, &"normal")
	var food := Registry.item(&"boiled_potatoes").food
	v.hunger = 10.0
	v.eat(food, 1.0, "", &"boiled_potatoes")
	var first := v.hunger - 10.0
	for i in 4:
		v.eat(food, 1.0, "", &"boiled_potatoes")
	var h := v.hunger
	v.eat(food, 1.0, "", &"boiled_potatoes")
	assert_lt(v.hunger - h, first * 0.6, "пятая тарелка подряд сытит хуже")
	var w := PlayerVitals.from_registry(Registry, &"normal")
	w.hunger = 10.0
	w.eat(food, 1.0, "", &"x", 1.5)
	assert_almost_eq(w.hunger - 10.0, first * 1.5, 0.01, "шедевр сытнее")


func test_food_buffs() -> void:
	var v := PlayerVitals.from_registry(Registry, &"normal")
	v.eat(Registry.item(&"roast_bear").food, 1.0, "", &"roast_bear")
	assert_almost_eq(v.mine_mult(), 1.25, 0.001, "медвежатина даёт силу")
	v.eat(Registry.item(&"ukha").food, 1.0, "", &"ukha")
	assert_gt(v.night_vision(), 0.0, "уха — ночное зрение")
	var s := PlayerVitals.from_registry(Registry, &"normal")
	s.eat(Registry.item(&"roast_bear").food, 0.1, "", &"roast_bear")
	assert_almost_eq(s.mine_mult(), 1.0, 0.001, "испорченное не даёт баффов")
