extends GutTest
## Сборка инструментов из частей: свойства по материалам, качество, закалка, заточка, имена.

var data: CraftingData


func before_all() -> void:
	data = CraftingData.new(Registry)


static func part(id: StringName, mat: String, q: int = 1, extra: Dictionary = {}) -> ItemStack:
	var s := ItemStack.make(id, 1, { "material": mat, "quality": q })
	s.data.merge(extra)
	return s


func _tool(head_mat: String, handle_mat: String = "oak", bind_mat: String = "leather", q: int = 1, extra: Dictionary = {}) -> ItemStack:
	return ToolAssembly.make(data, &"pickaxe", part(&"pickaxe_head", head_mat, q, extra), part(&"haft", handle_mat),
		part(&"binding", bind_mat))


func test_materials_change_stats() -> void:
	var copper := _tool("copper")
	var steel := _tool("steel")
	var stone := _tool("stone")
	for k in ["speed", "damage"]:
		assert_gt(float(steel.data["stats"][k]), float(copper.data["stats"][k]), k)
	assert_gt(int(steel.data["max_durability"]), int(copper.data["max_durability"]))
	assert_gt(int(copper.data["max_durability"]), int(stone.data["max_durability"]))
	assert_eq(int(steel.data["stats"]["tier"]), 5)
	assert_eq(int(stone.data["stats"]["tier"]), 1)
	# Рукоять и обмотка тоже важны.
	var oak := _tool("iron", "oak", "leather")
	var willow := _tool("iron", "linden", "twine")
	assert_gt(int(oak.data["max_durability"]), int(willow.data["max_durability"]))


func test_quality_quench_sharpen() -> void:
	var plain := _tool("iron")
	var master := _tool("iron", "oak", "leather", 4)
	assert_gt(float(master.data["stats"]["speed"]), float(plain.data["stats"]["speed"]))
	assert_gt(int(master.data["quality"]), int(plain.data["quality"]))
	var q := _tool("iron", "oak", "leather", 1, { "quenched": true })
	assert_gt(int(q.data["max_durability"]), int(plain.data["max_durability"]))
	var sh := _tool("iron", "oak", "leather", 1, { "sharpened": true })
	assert_gt(float(sh.data["stats"]["damage"]), float(plain.data["stats"]["damage"]))


func test_names() -> void:
	var def := Registry.item(&"pickaxe")
	assert_eq(ToolAssembly.display_name(_tool("steel"), def, data), "Стальная кирка")
	var axe := ToolAssembly.make(data, &"axe", part(&"axe_head", "flint"), part(&"haft", "wood"), part(&"binding", "twine"))
	assert_eq(ToolAssembly.display_name(axe, Registry.item(&"axe"), data), "Кремнёвый топор")
	var spear := ToolAssembly.make(data, &"spear", part(&"spear_head", "bronze"), part(&"haft", "oak"), part(&"binding", "rope"))
	assert_eq(ToolAssembly.display_name(spear, Registry.item(&"spear"), data), "Бронзовое копьё")
	var p := part(&"axe_head", "iron", 1, { "quenched": true })
	assert_eq(ToolAssembly.display_name(p, Registry.item(&"axe_head"), data), "Лезвие топора (железо, закалено)")


func test_check() -> void:
	var h := part(&"pickaxe_head", "iron")
	assert_eq(ToolAssembly.check(data, &"pickaxe", h, part(&"haft", "oak"), part(&"binding", "twine")), "")
	assert_ne(ToolAssembly.check(data, &"pickaxe", h, part(&"grip", "oak"), part(&"binding", "twine")), "", "не та рукоять")
	assert_ne(ToolAssembly.check(data, &"axe", h, part(&"haft", "oak"), part(&"binding", "twine")), "", "не то навершие")
	assert_ne(ToolAssembly.check(data, &"pickaxe", h, part(&"haft", "oak"), part(&"binding", "twine"), ["stone"]), "",
		"руками — только каменные")


func test_tool_of_and_breaking() -> void:
	var s := _tool("steel")
	var def := Registry.item(&"pickaxe")
	var t := ToolAssembly.tool_of(s, def)
	assert_eq(t["type"], &"pickaxe")
	assert_eq(int(t["tier"]), 5)
	var granite := Registry.block(&"granite")
	assert_gt(BlockInteraction.break_speed(granite, def, s), BlockInteraction.break_speed(granite, def, _tool("stone")))


func test_salvage() -> void:
	var s := _tool("bronze", "oak", "leather", 2)
	var back := ToolAssembly.salvage(s, Registry.item(&"pickaxe"))
	assert_eq(back.size(), 2, "навершие и рукоять, обмотка пропадает")
	assert_eq(back[0].id, &"pickaxe_head")
	assert_eq(String(back[0].data["material"]), "bronze")
	s.data["durability"] = 10
	back = ToolAssembly.salvage(s, Registry.item(&"pickaxe"))
	assert_eq(back.size(), 1, "изношенный — рукоять не спасти")
	assert_eq(int(back[0].data["quality"]), 1, "и навершие хуже")


func test_repair() -> void:
	var s := _tool("iron")
	var mx := int(s.data["max_durability"])
	s.data["durability"] = 10
	var units := Crafting.repair_units(data, s)
	assert_gt(units, 1)
	var r := Crafting.repaired(data, s, units)
	assert_lt(int(r.data["max_durability"]), mx, "ремонт понемногу снижает предел")
	assert_eq(int(r.data["durability"]), int(r.data["max_durability"]))
	assert_eq(Crafting.repair_inputs(data, s, 2)[0]["id"], "iron_ingot")
