extends GutTest
## Ручное ремесло: палки, бечёвка, кремнёвые части, сборка ножа, нужен инструмент; книга рецептов.

var data: CraftingData
var inv: PlayerInventory


func before_all() -> void:
	data = CraftingData.new(Registry)


func before_each() -> void:
	inv = PlayerInventory.new(Registry)


func test_sticks_and_twine() -> void:
	inv.add(ItemStack.make(&"birch_log", 1))
	inv.add(ItemStack.make(&"plant_fiber", 6))
	assert_true(Crafting.craft_hand(data, data.recipe(&"hand_sticks"), inv)["ok"])
	assert_eq(inv.count_of(&"stick"), 4)
	assert_eq(inv.count_of(&"birch_log"), 0)
	Crafting.craft_hand(data, data.recipe(&"hand_twine"), inv)
	Crafting.craft_hand(data, data.recipe(&"hand_twine"), inv)
	assert_eq(inv.count_of(&"twine"), 2)
	var r := Crafting.craft_hand(data, data.recipe(&"hand_twine"), inv)
	assert_false(r["ok"])
	assert_eq(r["reason"], "не хватает материалов")


func test_flint_knife_chain() -> void:
	inv.add(ItemStack.make(&"flint", 1))
	inv.add(ItemStack.make(&"stick", 1))
	inv.add(ItemStack.make(&"twine", 1))
	for id in [&"hand_flint_knife_blade", &"hand_grip", &"hand_binding_twine"]:
		assert_true(Crafting.craft_hand(data, data.recipe(id), inv)["ok"], String(id))
	var blade := _find(&"knife_blade")
	assert_eq(String(blade.data["material"]), "flint")
	assert_eq(String(_find(&"grip").data["material"]), "wood")
	assert_eq(String(_find(&"binding").data["material"]), "twine")
	assert_true(Crafting.craft_hand(data, data.recipe(&"hand_assemble_knife"), inv)["ok"])
	var knife := _find(&"knife")
	assert_not_null(knife)
	assert_eq(ToolAssembly.display_name(knife, Registry.item(&"knife"), data), "Кремнёвый нож")
	assert_null(_find(&"knife_blade"), "части ушли в нож")


func test_metal_cannot_be_assembled_by_hand() -> void:
	inv.add(ItemStack.make(&"pickaxe_head", 1, { "material": "iron", "quality": 1 }))
	inv.add(ItemStack.make(&"haft", 1, { "material": "oak", "quality": 1 }))
	inv.add(ItemStack.make(&"binding", 1, { "material": "rope", "quality": 1 }))
	var r := Crafting.craft_hand(data, data.recipe(&"hand_assemble_pickaxe"), inv)
	assert_false(r["ok"], "железо — только на верстаке")


func test_needs_tool() -> void:
	inv.add(ItemStack.make(&"oak_log", 4))
	var r := Crafting.craft_hand(data, data.recipe(&"hand_workbench"), inv)
	assert_false(r["ok"])
	assert_string_contains(String(r["reason"]), "топор")
	var axe := ToolAssembly.make(data, &"axe", ItemStack.make(&"axe_head", 1, { "material": "flint" }),
		ItemStack.make(&"haft", 1, { "material": "wood" }), ItemStack.make(&"binding", 1, { "material": "twine" }))
	inv.add(axe)
	var before := int(axe.data["durability"])
	assert_true(Crafting.craft_hand(data, data.recipe(&"hand_workbench"), inv)["ok"])
	assert_eq(inv.count_of(&"workbench"), 1)
	assert_eq(int(_find(&"axe").data["durability"]), before - 1, "топор износился")


func test_ingot_forging_material() -> void:
	var smith := PlayerInventory.new(Registry)
	smith.add(ItemStack.make(&"bronze_ingot", 2, { "quality": 2 }))
	smith.add(ItemStack.make(&"copper_ingot", 5, { "quality": 1 }))
	var r := data.recipe(&"forge_pickaxe_head")
	var invs: Array = smith.storages()
	assert_true(Ingredients.can_take(data, r["inputs"], invs), "меди хватает на 3")
	var mats := Ingredients.ingot_materials(data, invs, 3)
	assert_eq(mats.size(), 1, "бронзы мало — только медь")
	var got := Ingredients.take(data, r["inputs"], invs)
	assert_eq(Ingredients.material_from(data, got), &"copper")
	var outs := Crafting.outputs(data, r, got, 0.6, { "material": &"copper" })
	assert_eq(String(outs[0].data["material"]), "copper")
	assert_eq(smith.count_of(&"copper_ingot"), 2)


func test_recipe_book() -> void:
	var book := RecipeBook.new(data)
	assert_true(book.is_known(&"hand_sticks"), "простейшее известно сразу")
	assert_false(book.is_known(&"smelt_iron"))
	var opened := book.note_items([&"iron_concentrate"])
	assert_true(opened.has(&"smelt_iron"), "увидел концентрат — открылась плавка")
	assert_false(book.is_known(&"alloy_steel"), "сталь — только по чертежу")
	book.note_items([&"iron_ingot", &"charcoal"])
	assert_false(book.is_known(&"alloy_steel"))
	assert_true(book.use_blueprint(&"blueprint_steel").has(&"alloy_steel"))
	var b2 := RecipeBook.new(data)
	b2.from_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	assert_true(b2.is_known(&"alloy_steel"))
	assert_true(b2.seen.has(&"iron_ingot"))


func _find(id: StringName) -> ItemStack:
	for st: Inventory in inv.storages():
		for i in st.size():
			var s := st.get_stack(i)
			if s != null and s.id == id:
				return s
	return null
