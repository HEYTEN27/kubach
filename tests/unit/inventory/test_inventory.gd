extends GutTest
## Инвентарь: стопки, правила стаков, добавление, сортировка, вес, сохранение.


func _stack(id: StringName, n: int = 1) -> ItemStack:
	return ItemStack.create(Registry.item(id), n)


func test_blocks_are_items() -> void:
	var granite := Registry.item(&"granite")
	assert_not_null(granite)
	assert_eq(granite.place_block, Registry.block_num(&"granite"))
	assert_eq(granite.stack, 64)
	assert_null(Registry.item(&"water"), "у воды нет предмета")
	assert_null(Registry.item(&"bedrock"), "у материнской породы нет предмета")
	assert_not_null(Registry.item(&"stick"))
	assert_eq(Registry.item(&"torch").equip, &"offhand", "факел — во вторую руку")


func test_tools_do_not_stack() -> void:
	assert_eq(Registry.item(&"iron_pickaxe").stack, 1)
	assert_eq(Registry.item(&"fur_coat").stack, 1)
	var inv := Inventory.new(Registry, 3)
	assert_eq(inv.add(_stack(&"stone_axe")), 0)
	assert_eq(inv.add(_stack(&"stone_axe")), 0)
	assert_null(inv.get_stack(2))
	assert_eq(inv.get_stack(1).count, 1)


func test_add_merges_then_fills() -> void:
	var inv := Inventory.new(Registry, 2)
	assert_eq(inv.add(_stack(&"granite", 40)), 0)
	assert_eq(inv.add(_stack(&"granite", 40)), 0)
	assert_eq(inv.get_stack(0).count, 64)
	assert_eq(inv.get_stack(1).count, 16)
	var rest := inv.add(_stack(&"granite", 60))
	assert_eq(rest, 12, "не влезло 12")


func test_food_freshness_does_not_merge() -> void:
	var a := _stack(&"bilberries", 3)
	var b := _stack(&"bilberries", 3)
	b.data["freshness"] = 0.5
	var inv := Inventory.new(Registry, 4)
	inv.add(a)
	inv.add(b)
	assert_eq(inv.get_stack(0).count, 3)
	assert_eq(inv.get_stack(1).count, 3, "еда разной свежести — в разных стопках")


func test_remove_and_count() -> void:
	var inv := Inventory.new(Registry, 4)
	inv.add(_stack(&"stick", 10))
	inv.add(_stack(&"flint", 2))
	assert_eq(inv.count_of(&"stick"), 10)
	assert_eq(inv.remove(&"stick", 4), 4)
	assert_eq(inv.count_of(&"stick"), 6)
	assert_eq(inv.remove(&"flint", 5), 2)
	assert_eq(inv.count_of(&"flint"), 0)


func test_sort_merges_and_groups() -> void:
	var inv := Inventory.new(Registry, 6)
	inv.set_stack(0, _stack(&"stick", 5))
	inv.set_stack(2, _stack(&"granite", 10))
	inv.set_stack(4, _stack(&"stick", 7))
	inv.sort()
	var ids := []
	for s: ItemStack in inv.slots:
		if s != null:
			ids.append([s.id, s.count])
	assert_eq(ids.size(), 2, "палки слились")
	assert_has(ids, [&"stick", 12])


func test_equipment_slots_accept_only_their_kind() -> void:
	var p := PlayerInventory.new(Registry)
	var head := 0
	assert_true(p.equipment.accepts(head, _stack(&"fur_hat")))
	assert_false(p.equipment.accepts(head, _stack(&"fur_coat")))
	assert_false(p.equipment.accepts(head, _stack(&"granite")))
	assert_true(p.equipment.accepts(PlayerInventory.OFFHAND_SLOT, _stack(&"torch")))


func test_backpack_adds_slots_and_keeps_contents() -> void:
	var p := PlayerInventory.new(Registry)
	assert_eq(p.backpack.size(), 0)
	var bag := _stack(&"travel_backpack")
	p.equipment.set_stack(PlayerInventory.BACK_SLOT, bag)
	assert_eq(p.backpack.size(), 18)
	p.backpack.add(_stack(&"flint", 5))
	# Сняли рюкзак — ячейки пропали, а кремень остался внутри рюкзака.
	p.equipment.set_stack(PlayerInventory.BACK_SLOT, null)
	assert_eq(p.backpack.size(), 0)
	assert_true(bag.data.has("contents"))
	p.equipment.set_stack(PlayerInventory.BACK_SLOT, bag)
	assert_eq(p.backpack.count_of(&"flint"), 5)
	assert_false(p.backpack.accepts(0, _stack(&"small_backpack")), "рюкзак в рюкзак нельзя")


func test_weight_and_overload() -> void:
	var p := PlayerInventory.new(Registry)
	assert_eq(p.overload_factor(), 1.0)
	for i in 9:
		p.main.add(_stack(&"chest_iron", 1))
	assert_gt(p.total_weight(), PlayerInventory.CARRY_LIMIT)
	assert_lt(p.overload_factor(), 1.0)


func test_save_and_load() -> void:
	var p := PlayerInventory.new(Registry)
	p.hotbar.set_stack(0, _stack(&"stone_pickaxe"))
	p.hotbar.get_stack(0).data["durability"] = 50
	p.main.add(_stack(&"stick", 12))
	var bag := _stack(&"small_backpack")
	p.equipment.set_stack(PlayerInventory.BACK_SLOT, bag)
	p.backpack.add(_stack(&"flint", 3))
	p.select(4)
	var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var q := PlayerInventory.new(Registry)
	q.from_dict(d)
	assert_eq(int(q.hotbar.get_stack(0).data["durability"]), 50)
	assert_eq(q.main.count_of(&"stick"), 12)
	assert_eq(q.backpack.size(), 9)
	assert_eq(q.backpack.count_of(&"flint"), 3)
	assert_eq(q.selected, 4)


func test_unknown_item_skipped_on_load() -> void:
	var inv := Inventory.new(Registry, 2)
	inv.from_array([{ "id": "no_such_item", "n": 3 }, { "id": "stick", "n": 2 }])
	assert_null(inv.get_stack(0))
	assert_eq(inv.get_stack(1).count, 2)
	assert_push_warning("no_such_item")


func test_durability_and_breaking() -> void:
	var p := PlayerInventory.new(Registry)
	p.hotbar.set_stack(0, _stack(&"stone_axe"))
	p.hotbar.get_stack(0).data["durability"] = 2
	assert_false(p.damage_held())
	assert_true(p.damage_held(), "инструмент сломался")
	assert_null(p.held())


func test_hand_light_from_offhand_torch() -> void:
	var p := PlayerInventory.new(Registry)
	assert_eq(p.hand_light()[0], 0)
	p.equipment.set_stack(PlayerInventory.OFFHAND_SLOT, _stack(&"torch", 4))
	assert_eq(p.hand_light()[0], 14)
