extends GutTest
## Предметы на земле: падают, подбираются, сливаются, сохраняются; скорость добычи инструментом.

var world: World
var dropped: DroppedItems
var inv: PlayerInventory
var body: VoxelBody


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 7)
	var col := ChunkColumn.new(Vector2i(0, 0))
	for z in 16:
		for x in 16:
			col.set_block(x, 60, z, Registry.block_num(&"granite"))
	world.chunks.columns[Vector2i(0, 0)] = col
	add_child(world)
	dropped = DroppedItems.new()
	world.add_child(dropped)
	dropped.setup(world)
	inv = PlayerInventory.new(Registry)
	body = VoxelBody.new(world.is_solid)
	body.set_position(8.5, 61.0, 8.5)
	dropped.inventory = inv
	dropped.player_body = body


func after_each() -> void:
	world.chunks.wait_all()
	world.free()


func _step(n: int) -> void:
	for i in n:
		dropped._physics_process(1.0 / 60.0)


func test_falls_to_ground() -> void:
	body.set_position(100.0, 61.0, 100.0)
	dropped.spawn(ItemStack.create(Registry.item(&"stick"), 3), 3.5, 65.0, 3.5)
	_step(120)
	var d: Array = dropped.to_array()
	assert_eq(d.size(), 1)
	assert_almost_eq(float(d[0]["y"]), 61.0, 0.05, "лежит на камне")


func test_pickup_after_delay() -> void:
	dropped.spawn(ItemStack.create(Registry.item(&"flint"), 4), 8.5, 61.2, 8.5, 0.0, 0.0, 0.0, 0.5)
	_step(10)
	assert_eq(inv.count_of(&"flint"), 0, "сразу не подбирается")
	_step(40)
	assert_eq(inv.count_of(&"flint"), 4)
	assert_eq(dropped.count(), 0)


func test_merge_nearby() -> void:
	body.set_position(100.0, 61.0, 100.0)
	dropped.spawn(ItemStack.create(Registry.item(&"stick"), 3), 3.5, 61.1, 3.5)
	dropped.spawn(ItemStack.create(Registry.item(&"stick"), 5), 3.7, 61.1, 3.6)
	_step(70)
	assert_eq(dropped.count(), 1)
	assert_eq(int(dropped.to_array()[0]["item"]["n"]), 8)


func test_world_drop_signal_spawns() -> void:
	world.game_mode = &"survival"
	world.set_block(3, 61, 3, Registry.block_num(&"chest_wood"))
	world.execute(GameAction.break_block(Vector3i(3, 61, 3)))
	assert_eq(dropped.count(), 1, "сундук выпал предметом")


func test_save_roundtrip() -> void:
	body.set_position(100.0, 61.0, 100.0)
	dropped.spawn(ItemStack.create(Registry.item(&"stick"), 2), 4.5, 61.0, 4.5)
	var arr := dropped.to_array()
	var d2 := DroppedItems.new()
	world.add_child(d2)
	d2.setup(world)
	d2.from_array(JSON.parse_string(JSON.stringify(arr)))
	assert_eq(d2.count(), 1)


func test_tool_speed() -> void:
	var granite := Registry.block(&"granite")
	var leaves := Registry.block(&"oak_leaves")
	assert_eq(BlockInteraction.break_speed(granite, null), 1.0)
	assert_gt(BlockInteraction.break_speed(granite, Registry.item(&"iron_pickaxe")), 5.0)
	assert_eq(BlockInteraction.break_speed(granite, Registry.item(&"iron_axe")), 1.0, "топор по камню не помогает")
	assert_gt(BlockInteraction.break_speed(leaves, Registry.item(&"shears")), 1.0)
