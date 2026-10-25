extends GutTest
## Контроллер ремесла: рецепты станций из инвентаря игрока, ковка требует жара и уровня
## наковальни, сборка и ремонт на верстаке, чтение чертежа.

var world: World
var system: StationSystem
var ctl: CraftingController
var player: Player


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 5)
	world.game_mode = &"survival"
	var col := ChunkColumn.new(Vector2i(0, 0))
	var stone := Registry.block_num(&"granite")
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, stone)
	world.chunks.columns[Vector2i(0, 0)] = col
	system = StationSystem.new()
	add_child_autofree(system)
	system.setup(world, CraftingData.shared(Registry), GameClock.new())
	player = Player.new()
	player.world = world
	player.inventory = PlayerInventory.new(Registry)
	ctl = CraftingController.new()
	ctl.world = world
	ctl.player = player
	ctl.stations = system
	ctl.data = CraftingData.shared(Registry)
	ctl.book = RecipeBook.new(ctl.data)
	ctl.minigames = false
	add_child_autofree(ctl)


func after_each() -> void:
	player.free()
	world.free()


func _place(id: StringName, p: Vector3i) -> Station:
	world.execute(GameAction.place_block(p, Registry.block_num(id)))
	return system.station_at(p)


func test_recipe_from_player_inventory() -> void:
	var p := Vector3i(3, 61, 3)
	var st := _place(&"carpenter_table", p)
	player.inventory.add(ItemStack.make(&"oak_log", 2))
	ctl.book.note_inventory(player.inventory)
	var r := ctl.data.recipe(&"oak_planks")
	assert_true(ctl.book.is_known(&"oak_planks"), "увидел бревно — знаешь доски")
	assert_eq(ctl.available(r), 2)
	assert_true(ctl.start_recipe(st, p, r, 2))
	assert_eq(player.inventory.count_of(&"oak_log"), 0)
	assert_eq(st.queue.size() + (0 if st.job.is_empty() else 1), 2)
	st.advance(10.0)
	assert_eq(st.outputs.count_of(&"oak_planks"), 8)


func test_forge_needs_heat_and_tier() -> void:
	var a := Vector3i(5, 61, 5)
	var anvil := _place(&"stone_anvil", a)
	player.inventory.add(ItemStack.make(&"iron_ingot", 3, { "quality": 1 }))
	player.inventory.add(ItemStack.make(&"copper_ingot", 3, { "quality": 1 }))
	var r := ctl.data.recipe(&"forge_pickaxe_head")
	assert_string_contains(ctl.recipe_blocker(anvil, a, r, &"copper"), "горн", "без жара не куют")
	var f := Vector3i(6, 61, 5)
	var furnace := _place(&"stone_furnace", f)
	furnace.fuel.set_stack(0, ItemStack.make(&"coal", 4))
	furnace.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 8))
	furnace.auto = false
	furnace.advance(20.0)
	assert_eq(ctl.recipe_blocker(anvil, a, r, &"copper"), "", "медь на каменной наковальне у печи")
	assert_string_contains(ctl.recipe_blocker(anvil, a, r, &"iron"), "слабая", "железо — нужна бронзовая наковальня")
	assert_true(ctl.start_recipe(anvil, a, r, 1, &"copper"))
	assert_eq(player.inventory.count_of(&"copper_ingot"), 0)
	anvil.advance(15.0)
	var head := anvil.outputs.get_stack(0)
	assert_eq(head.id, &"pickaxe_head")
	assert_eq(String(head.data["material"]), "copper")


func test_assembly_and_repair_on_workbench() -> void:
	var p := Vector3i(8, 61, 8)
	var wb := _place(&"workbench", p)
	wb.inputs.set_stack(0, ItemStack.make(&"axe_head", 1, { "material": "iron", "quality": 1 }))
	wb.inputs.set_stack(1, ItemStack.make(&"haft", 1, { "material": "birch", "quality": 1 }))
	wb.inputs.set_stack(2, ItemStack.make(&"binding", 1, { "material": "rope", "quality": 1 }))
	var pv := ctl.assembly_preview(wb)
	assert_eq(int(pv["tier"]), 4)
	assert_true(ctl.assemble(wb))
	wb.advance(11.0)
	var axe := wb.outputs.get_stack(0)
	assert_eq(axe.id, &"axe")
	wb.outputs.set_stack(0, null)
	axe.data["durability"] = 5
	wb.inputs.set_stack(0, axe)
	assert_false(ctl.repair(wb), "нет железа — не починить")
	player.inventory.add(ItemStack.make(&"iron_ingot", 5))
	assert_true(ctl.repair(wb))
	wb.advance(20.0)
	var fixed := wb.outputs.get_stack(0)
	assert_eq(int(fixed.data["durability"]), int(fixed.data["max_durability"]))
	assert_lt(player.inventory.count_of(&"iron_ingot"), 5)


func test_blueprint() -> void:
	player.inventory.hotbar.set_stack(0, ItemStack.make(&"blueprint_steel", 1))
	assert_false(ctl.book.is_known(&"alloy_steel"))
	assert_true(ctl.read_blueprint())
	assert_true(ctl.book.is_known(&"alloy_steel"))
	assert_null(player.inventory.held(), "чертёж прочитан и убран")
