extends GutTest
## Игрок в настоящем мире: ходьба, прыжок, ломание и установка блоков через ввод, камера F5.

var world: World
var player: Player


func before_each() -> void:
	world = World.new()
	world.setup(Registry, null, 31337)
	world.chunks.view_distance = 2
	add_child(world)
	# Ровное место у начала: ищем сушу.
	var x := 0
	while world.generator.surface_height(x, 0) <= world.generator.sea_level:
		x += 7
	var h := world.generator.surface_height(x, 0)
	player = Player.new()
	player.setup(world, x + 0.5, h + 1.0, 0.5)
	add_child(player)
	player.force_input = true
	var cpos := Vector2i(x >> 4, 0)
	var deadline := Time.get_ticks_msec() + 20000
	while not world.chunks.is_area_ready(cpos, 1) and Time.get_ticks_msec() < deadline:
		world.chunks.update(cpos)
		OS.delay_msec(2)
	player.active = true


func after_each() -> void:
	for a in [&"move_forward", &"jump", &"attack", &"use"]:
		Input.action_release(a)
	world.chunks.wait_all()
	player.free()
	world.free()


func _frames(n: int) -> void:
	for i in n:
		world.chunks.update(Vector2i(floori(player.body.x) >> 4, floori(player.body.z) >> 4))
		await wait_physics_frames(1)


func test_walks_forward() -> void:
	var z0 := player.body.z
	var x0 := player.body.x
	Input.action_press(&"move_forward")
	await _frames(30)
	Input.action_release(&"move_forward")
	var moved := Vector2(player.body.x - x0, player.body.z - z0).length()
	assert_gt(moved, 0.3, "игрок сдвинулся")


func test_jump_leaves_ground_and_lands() -> void:
	await _frames(5)
	var y0 := player.body.y
	Input.action_press(&"jump")
	await _frames(8)
	Input.action_release(&"jump")
	assert_gt(player.body.y, y0 + 0.5, "в прыжке")
	await _frames(60)
	assert_true(player.body.on_ground)


func test_break_and_place_block_in_creative() -> void:
	world.game_mode = &"creative"
	await _frames(5)
	player.pitch = -PI * 0.5 + 0.01
	var below := Vector3i(floori(player.body.x), floori(player.body.y) - 1, floori(player.body.z))
	assert_ne(world.get_block(below.x, below.y, below.z), 0)
	Input.action_press(&"attack")
	await _frames(4)
	Input.action_release(&"attack")
	assert_eq(world.get_block(below.x, below.y, below.z), 0, "блок под ногами сломан")
	# Взлетаем на 3 блока над землёй и ставим гранит под собой.
	player.motor.flying = true
	var ground := Vector3i(below.x, world.generator.surface_height(below.x + 3, below.z), below.z)
	ground.x += 3
	player.teleport(ground.x + 0.5, ground.y + 4.0, ground.z + 0.5)
	await _frames(3)
	var granite := Registry.block_num(&"granite")
	player.interaction.select(player.interaction.palette.find(granite))
	assert_eq(player.interaction.selected_block(), granite)
	var target := ground + Vector3i.UP
	# Растения, снег и листву над точкой убираем: цель луча должна быть землёй.
	for dy in range(1, 8):
		world.set_block(ground.x, ground.y + dy, ground.z, 0)
	world.set_block(ground.x, ground.y, ground.z, Registry.block_num(&"loam"))
	await _frames(2)
	assert_eq(world.get_block(target.x, target.y, target.z), 0, "над землёй пусто")
	Input.action_press(&"use")
	await _frames(3)
	Input.action_release(&"use")
	assert_eq(world.get_block(target.x, target.y, target.z), granite,
		"гранит поставлен на землю; цель луча: %s" % player.interaction.target)


func test_survival_breaking_takes_time() -> void:
	await _frames(5)
	player.pitch = -PI * 0.5 + 0.01
	var below := Vector3i(floori(player.body.x), floori(player.body.y) - 1, floori(player.body.z))
	var def := Registry.block_by_num(world.get_block(below.x, below.y, below.z))
	Input.action_press(&"attack")
	await _frames(10)
	assert_ne(world.get_block(below.x, below.y, below.z), 0, "за 10 кадров %s не ломается" % def.id)
	assert_gt(player.interaction.break_progress, 0.0)
	await _frames(int(def.hardness * 60.0) + 20)
	Input.action_release(&"attack")
	assert_eq(world.get_block(below.x, below.y, below.z), 0, "сломался примерно за hardness секунд")


func test_camera_modes_cycle_smoothly() -> void:
	player.set_camera_mode(Player.CameraMode.THIRD_BACK)
	await _frames(2)
	var mid := player.camera.position.length()
	await _frames(60)
	var far := player.camera.position.length()
	assert_gt(far, mid, "камера отъезжает плавно, а не скачком")
	assert_true(player.model.visible)
	player.set_camera_mode(Player.CameraMode.FIRST_PERSON)
	await _frames(60)
	assert_false(player.model.visible)
	assert_almost_eq(player.camera.position.y, PlayerMotor.STAND_EYE, 0.05)
