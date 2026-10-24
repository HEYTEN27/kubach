extends GutTest
## Клики окна инвентаря: курсор, половина, по одной, Shift, двойной клик, корзина, сундук.

var p: PlayerInventory
var ops: InventoryOps


func before_each() -> void:
	p = PlayerInventory.new(Registry)
	ops = InventoryOps.new(p)


func _stack(id: StringName, n: int = 1) -> ItemStack:
	return ItemStack.create(Registry.item(id), n)


func test_left_pick_place_merge_swap() -> void:
	p.main.set_stack(0, _stack(&"granite", 10))
	p.main.set_stack(1, _stack(&"granite", 60))
	p.main.set_stack(2, _stack(&"stick", 3))
	assert_true(ops.left_click(p.main, 0))
	assert_eq(ops.cursor.count, 10)
	assert_null(p.main.get_stack(0))
	assert_true(ops.left_click(p.main, 1), "сложить до 64")
	assert_eq(p.main.get_stack(1).count, 64)
	assert_eq(ops.cursor.count, 6)
	assert_true(ops.left_click(p.main, 2), "поменять местами")
	assert_eq(ops.cursor.id, &"stick")
	assert_eq(p.main.get_stack(2).id, &"granite")
	assert_true(ops.left_click(p.main, 0))
	assert_null(ops.cursor)


func test_right_half_and_one() -> void:
	p.main.set_stack(0, _stack(&"stick", 7))
	assert_true(ops.right_click(p.main, 0))
	assert_eq(ops.cursor.count, 4, "половина с округлением вверх")
	assert_eq(p.main.get_stack(0).count, 3)
	assert_true(ops.right_click(p.main, 5))
	assert_eq(p.main.get_stack(5).count, 1)
	assert_eq(ops.cursor.count, 3)


func test_right_drag_distributes_one_each() -> void:
	ops.cursor = _stack(&"flint", 3)
	for i in [0, 1, 1, 2, 3]:
		ops.right_drag(p.main, i)
	ops.end_drag()
	assert_eq(p.main.get_stack(0).count, 1)
	assert_eq(p.main.get_stack(1).count, 1, "повторный заход в ячейку не кладёт вторую штуку")
	assert_eq(p.main.get_stack(2).count, 1)
	assert_null(p.main.get_stack(3))
	assert_null(ops.cursor)


func test_shift_moves_hotbar_to_main_and_equips() -> void:
	p.hotbar.set_stack(0, _stack(&"stick", 5))
	assert_true(ops.shift_click(p.hotbar, 0))
	assert_null(p.hotbar.get_stack(0))
	assert_eq(p.main.count_of(&"stick"), 5)
	p.main.set_stack(3, _stack(&"leather_cap"))
	assert_true(ops.shift_click(p.main, 3))
	assert_eq(p.equipment.get_stack(0).id, &"leather_cap", "Shift+клик надевает")
	assert_true(ops.shift_click(p.equipment, 0))
	assert_null(p.equipment.get_stack(0), "и снимает")


func test_equipment_rejects_wrong_item() -> void:
	ops.cursor = _stack(&"granite", 5)
	assert_false(ops.left_click(p.equipment, 0))
	assert_eq(ops.cursor.count, 5)


func test_double_click_collects() -> void:
	p.main.set_stack(0, _stack(&"stick", 5))
	p.main.set_stack(7, _stack(&"stick", 9))
	p.hotbar.set_stack(2, _stack(&"stick", 4))
	assert_true(ops.double_click(p.main, 0))
	assert_eq(ops.cursor.count, 18)
	assert_eq(p.main.count_of(&"stick") + p.hotbar.count_of(&"stick"), 0)


func test_trash_only_in_creative() -> void:
	ops.cursor = _stack(&"stick", 2)
	assert_false(ops.trash())
	ops.creative = true
	assert_true(ops.trash())
	assert_null(ops.cursor)


func test_creative_take() -> void:
	assert_false(ops.take_creative(&"granite"))
	ops.creative = true
	assert_true(ops.take_creative(&"granite"))
	assert_eq(ops.cursor.count, 64)


func test_container_shift_and_deposit_similar() -> void:
	ops.container = Inventory.new(Registry, 27, "container")
	ops.container.set_stack(0, _stack(&"granite", 1))
	p.main.set_stack(0, _stack(&"granite", 30))
	p.main.set_stack(1, _stack(&"stick", 30))
	assert_true(ops.deposit_similar())
	assert_eq(ops.container.count_of(&"granite"), 31)
	assert_eq(p.main.count_of(&"stick"), 30, "палок в сундуке не было — остались")
	assert_true(ops.shift_click(p.main, 1))
	assert_eq(ops.container.count_of(&"stick"), 30)
	assert_true(ops.shift_click(ops.container, 0))
	assert_gt(p.hotbar.count_of(&"granite") + p.main.count_of(&"granite"), 0)


func test_drop_and_close() -> void:
	var dropped: Array = []
	ops.dropped.connect(func(s: ItemStack) -> void: dropped.append(s))
	p.hotbar.set_stack(0, _stack(&"stick", 5))
	assert_true(ops.drop_slot(p.hotbar, 0, 1))
	assert_eq(dropped[0].count, 1)
	assert_eq(p.hotbar.get_stack(0).count, 4)
	ops.cursor = _stack(&"flint", 2)
	ops.close()
	assert_null(ops.cursor)
	assert_eq(p.count_of(&"flint"), 2, "с курсора вернулось в инвентарь")


func test_execute_action() -> void:
	p.main.set_stack(0, _stack(&"stick", 2))
	assert_true(ops.execute(InventoryAction.make(InventoryAction.Op.LEFT, "main", 0)))
	assert_eq(ops.cursor.count, 2)
	assert_true(ops.execute(InventoryAction.make(InventoryAction.Op.LEFT, "hotbar", 3)))
	assert_eq(p.hotbar.get_stack(3).count, 2)
