extends GutTest
## Станции: процессы во времени, топливо и жар, вода, плавка с баллом, сплав, готовка с
## зонами, очередь рецептов, сборка, выход занят, досчёт времени, сохранение.

var data: CraftingData


func before_all() -> void:
	data = CraftingData.new(Registry)


func _st(kind: StringName, tier: int = 1) -> Station:
	var s := Station.new(data, kind, tier)
	s.rng.seed = 7
	return s


func test_crusher_process() -> void:
	var s := _st(&"crusher")
	s.inputs.set_stack(0, ItemStack.make(&"malachite_ore", 2))
	var ev := s.advance(5.0)
	assert_true(ev.is_empty(), "6 минут ещё не прошло")
	ev = s.advance(1.5)
	assert_eq(ev.size(), 1)
	assert_eq(s.outputs.count_of(&"crushed_copper"), 2)
	s.advance(10.0)
	assert_eq(s.outputs.count_of(&"crushed_copper"), 4, "второй кусок руды тоже")
	assert_true(s.inputs.is_empty())


func test_washing_needs_water() -> void:
	var s := _st(&"washing")
	s.inputs.set_stack(0, ItemStack.make(&"crushed_iron", 1))
	s.advance(20.0, { "water": false })
	assert_eq(s.outputs.count_of(&"iron_concentrate"), 0)
	assert_ne(s.blocker({ "water": false }), "")
	s.advance(20.0, { "water": true })
	assert_eq(s.outputs.count_of(&"iron_concentrate"), 1)


func test_furnace_needs_fuel_and_heat() -> void:
	var s := _st(&"furnace")
	s.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 1))
	s.advance(30.0)
	assert_eq(s.outputs.count_of(&"tin_ingot"), 0, "без топлива не плавит")
	assert_eq(s.blocker(), "Нет топлива")
	assert_true(s.fuel.accepts(0, ItemStack.make(&"charcoal")))
	assert_false(s.fuel.accepts(0, ItemStack.make(&"granite")), "камень — не топливо")
	assert_false(s.outputs.accepts(0, ItemStack.make(&"charcoal")), "в выход класть нельзя")
	s.fuel.set_stack(0, ItemStack.make(&"charcoal", 4))
	s.advance(40.0)
	assert_eq(s.fuel.count_of(&"charcoal"), 2, "сожгли только нужное")
	assert_gt(s.temp, 232.0)
	assert_eq(s.outputs.count_of(&"tin_ingot"), 1)
	assert_true(s.outputs.get_stack(0).data.has("quality"), "у слитка есть качество")


func test_heat_too_low() -> void:
	var s := _st(&"bloomery")
	s.inputs.set_stack(0, ItemStack.make(&"iron_concentrate", 1))
	s.fuel.set_stack(0, ItemStack.make(&"stick", 60))   # 600 °C, мало для железа
	s.auto = false
	s.advance(30.0)
	assert_eq(s.outputs.count_of(&"iron_ingot"), 0)
	assert_string_contains(s.blocker(), "Мало жара")


func test_manual_smelt_scores_by_green_zone() -> void:
	# Олово (232 °C) на угле (1250 °C) без заслонки — перегрев, плохое качество.
	var hot := _st(&"furnace")
	hot.auto = false
	hot.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 1))
	hot.fuel.set_stack(0, ItemStack.make(&"coal", 3))
	hot.advance(60.0)
	var careful := _st(&"furnace")
	careful.auto = false
	careful.set_damper(0.25)   # 20 + (1000 − 20)·0.25 ≈ 265 °C — в зелёной зоне
	careful.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 1))
	careful.fuel.set_stack(0, ItemStack.make(&"coal", 3))
	careful.advance(60.0)
	var q_hot := int(hot.outputs.get_stack(0).data["quality"])
	var q_careful := int(careful.outputs.get_stack(0).data["quality"])
	assert_gt(q_careful, q_hot, "держал температуру — лучше качество")


func test_bellows_reach_iron() -> void:
	var s := _st(&"bloomery")
	s.auto = false
	s.inputs.set_stack(0, ItemStack.make(&"iron_concentrate", 1))
	s.fuel.set_stack(0, ItemStack.make(&"charcoal", 12))
	s.advance(20.0)
	assert_lt(s.temp, 1250.0, "уголь сам по себе даёт 1150")
	for i in 60:
		s.pump()
		s.advance(0.5)
	assert_eq(s.outputs.count_of(&"iron_ingot"), 1, "мехи догоняют до плавки железа")


func test_alloy_bronze() -> void:
	var s := _st(&"bloomery")
	s.inputs.set_stack(0, ItemStack.make(&"copper_ingot", 7))
	s.inputs.set_stack(1, ItemStack.make(&"tin_ingot", 1))
	s.fuel.set_stack(0, ItemStack.make(&"charcoal", 10))
	s.fuel.set_stack(1, ItemStack.make(&"charcoal", 10))
	s.advance(300.0)
	assert_eq(s.outputs.count_of(&"bronze_ingot"), 8, "сплав из 8 единиц")
	assert_eq(s.outputs.count_of(&"copper_ingot"), 0, "медь не переплавлена отдельно")


func test_cook_auto_and_manual() -> void:
	var auto := _st(&"campfire")
	auto.inputs.set_stack(0, ItemStack.make(&"raw_meat", 1))
	auto.fuel.set_stack(0, ItemStack.make(&"stick", 10))
	auto.advance(30.0)
	var meat := auto.outputs.get_stack(0)
	assert_eq(meat.id, &"cooked_meat")
	assert_false(meat.data.has("cook"), "авто — идеально")
	var manual := _st(&"campfire")
	manual.auto = false
	manual.inputs.set_stack(0, ItemStack.make(&"raw_meat", 2))
	manual.fuel.set_stack(0, ItemStack.make(&"oak_log", 4))
	manual.advance(4.0)
	assert_true(manual.take_cook(), "сняли рано")
	manual.advance(0.5)
	assert_eq(String(manual.outputs.get_stack(0).data.get("cook", "")), "under")
	manual.advance(40.0)
	assert_eq(manual.outputs.count_of(&"burnt_food"), 1, "забыли — сгорело")


func test_cook_zones() -> void:
	var r := data.recipe(&"cook_meat")
	assert_eq(Station.cook_zone(r, 0.5), "under")
	assert_eq(Station.cook_zone(r, 1.0), "perfect")
	assert_eq(Station.cook_zone(r, 1.5), "over")
	assert_eq(Station.cook_zone(r, 2.0), "burnt")


func test_output_blocked() -> void:
	var s := _st(&"tanning_rack")
	s.inputs.set_stack(0, ItemStack.make(&"raw_hide", 1))
	s._add_out(ItemStack.make(&"granite", 64))
	s._add_out(ItemStack.make(&"sand", 64))
	s.advance(100.0)
	assert_string_contains(s.blocker(), "Выход занят")
	s.outputs.set_stack(1, null)
	s.advance(1.0)
	assert_eq(s.outputs.count_of(&"scraped_hide"), 1)


func test_recipe_queue_and_assembly() -> void:
	var s := _st(&"workbench")
	var head := ItemStack.make(&"pickaxe_head", 1, { "material": "iron", "quality": 2 })
	s.inputs.set_stack(0, head)
	s.inputs.set_stack(1, ItemStack.make(&"haft", 1, { "material": "oak", "quality": 1 }))
	s.inputs.set_stack(2, ItemStack.make(&"binding", 1, { "material": "leather", "quality": 1 }))
	assert_eq(s.start_assembly(data.recipe(&"assemble_pickaxe")), "")
	assert_true(s.inputs.is_empty())
	s.advance(11.0)
	var tool := s.outputs.get_stack(0)
	assert_eq(tool.id, &"pickaxe")
	assert_eq(String(tool.data["parts"]["head"]["material"]), "iron")
	assert_ne(s.start_assembly(data.recipe(&"assemble_axe")), "", "пусто — нечего собирать")


func test_catch_up_and_save() -> void:
	var s := _st(&"tanning_barrel")
	s.inputs.set_stack(0, ItemStack.make(&"scraped_hide", 1))
	s.inputs.set_stack(1, ItemStack.make(&"oak_bark", 2))
	s.advance_to(1000.0)   # первая отметка времени
	var saved := JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary
	var b := _st(&"tanning_barrel")
	b.from_dict(saved)
	assert_false(b.job.is_empty(), "задание сохранилось")
	b.advance_to(1000.0 + 2 * 24 * 60 + 5)   # прошло двое суток, пока колонна была выгружена
	assert_eq(b.outputs.count_of(&"tanned_hide"), 1)


func test_all_items_for_drop() -> void:
	var s := _st(&"furnace")
	s.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 3))
	s.fuel.set_stack(0, ItemStack.make(&"coal", 2))
	s.advance(1.0)
	var n := 0
	for st in s.all_items():
		n += st.count
	assert_eq(n, 3 + 1, "2 концентрата во входе + 1 в работе; уголь: 1 горит, 1 в ячейке")
