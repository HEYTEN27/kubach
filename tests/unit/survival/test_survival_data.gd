extends GutTest
## Согласованность данных выживания: эффекты, лекарства, еда, кровати, тепло, вода биомов,
## сложности; выпадение вещей при смерти.


func test_effects_consistent() -> void:
	var ids := {}
	for e in Registry.get_entries("effects"):
		ids[String(e["id"])] = true
		assert_false((e["stages"] as Array).is_empty(), "%s: есть стадии" % e["id"])
	for e in Registry.get_entries("effects"):
		var nxt := String(e.get("next_effect", ""))
		if nxt != "":
			assert_true(ids.has(nxt), "%s: next_effect %s существует" % [e["id"], nxt])
		for c in e.get("cure_items", []):
			var item := Registry.item(StringName(c))
			assert_not_null(item, "%s: лекарство %s существует" % [e["id"], c])
			if item != null:
				assert_true(item.is_medicine() and (item.medicine.get("cures", []) as Array).has(String(e["id"])),
					"%s лечит %s" % [c, e["id"]])
	for id in ["frostbite", "heatstroke", "cold", "dysentery", "food_poisoning", "wound", "fracture", "splinted", "rested", "warm_meal"]:
		assert_true(ids.has(id), "эффект %s, нужный движку" % id)


func test_items_survival_fields() -> void:
	assert_true(Registry.item(&"cooked_meat").is_food())
	assert_true(Registry.item(&"bandage").is_medicine())
	assert_false(Registry.item(&"bandage").is_food())
	assert_true(Registry.item(&"porcini").is_food(), "грибы съедобны (блок-растение)")
	assert_true(Registry.item(&"plantain").is_medicine())
	assert_false(Registry.item(&"granite").is_consumable())


func test_blocks_heat_beds() -> void:
	# Костёр (этап 6) — станция: греет, только пока горит топливо.
	assert_eq(Registry.block(&"campfire").station_kind, &"campfire")
	assert_gt(float(Registry.get_entry("stations", &"campfire")["warmth"]), 10.0)
	assert_gt(Registry.block_heat[Registry.block_num(&"lava")], 10.0)
	assert_gt(Registry.block_contact[Registry.block_num(&"lava")], 10.0)
	assert_eq(Registry.block_heat[Registry.block_num(&"granite")], 0.0)
	for id: StringName in [&"sleeping_bag", &"bed", &"double_bed"]:
		assert_true(Registry.block(id).is_bed(), String(id))
		assert_not_null(Registry.item(id), "кровать можно поставить")
	assert_false(Registry.block(&"granite").is_bed())


func test_biome_water() -> void:
	var kinds := {}
	for e in Registry.get_entries("biomes"):
		kinds[String(e["id"])] = String(e.get("water_kind", "fresh"))
	assert_eq(kinds.get("ocean"), "sea")
	assert_eq(kinds.get("taiga_swamp"), "dirty")
	assert_eq(kinds.get("taiga"), "fresh")


func test_difficulties() -> void:
	for id: StringName in WorldGenSettings.DIFFICULTIES:
		assert_true(Registry.has_entry("difficulties", id), String(id))
	assert_true(Registry.get_entry("difficulties", &"hardcore").get("one_life", false))
	assert_false(Registry.get_entry("difficulties", &"peaceful").get("drop_on_death", true))


func test_take_all_drops_everything_with_backpack_contents() -> void:
	var inv := PlayerInventory.new(Registry)
	inv.hotbar.set_stack(0, ItemStack.create(Registry.item(&"granite"), 10))
	inv.main.set_stack(3, ItemStack.create(Registry.item(&"stick"), 5))
	var pack: ItemDef = null
	for d in Registry.items():
		if d.backpack_slots > 0:
			pack = d
			break
	assert_not_null(pack)
	inv.equipment.set_stack(PlayerInventory.BACK_SLOT, ItemStack.create(pack))
	inv.backpack.set_stack(0, ItemStack.create(Registry.item(&"bilberries"), 7))
	var all := inv.take_all()
	assert_eq(all.size(), 3)
	assert_true(inv.hotbar.is_empty() and inv.main.is_empty() and inv.equipment.is_empty())
	var bp: ItemStack = null
	for s in all:
		if s.id == pack.id:
			bp = s
	assert_not_null(bp)
	var n := 0
	for c in bp.data.get("contents", []):
		if c != null:
			n += 1
	assert_eq(n, 1, "содержимое рюкзака уходит вместе с ним")
