extends GutTest
## Физика игрока (раздел 4.1): один прыжок на 1,25 блока, стены, присед у края, граница мира.

const DT := 1.0 / 60.0

var world: FakeWorld
var body: VoxelBody
var motor: PlayerMotor


func before_each() -> void:
	world = FakeWorld.new()
	body = VoxelBody.new(world.is_solid)
	motor = PlayerMotor.new(body, world.is_fluid)
	body.set_position(0.5, 0.0, 0.5)
	_run(5)


func _run(ticks: int, wish := Vector2.ZERO, jump := false, sprint := false, crouch := false) -> void:
	for i in ticks:
		motor.step(DT, wish, jump, sprint, crouch)


func test_stands_on_floor() -> void:
	assert_true(body.on_ground)
	assert_almost_eq(body.y, 0.0, 1e-9)


func test_jump_height_is_1_25() -> void:
	var peak := 0.0
	motor.step(DT, Vector2.ZERO, true, false, false)
	for i in 120:
		motor.step(DT, Vector2.ZERO, false, false, false)
		peak = maxf(peak, body.y)
	assert_almost_eq(peak, 1.25, 0.01, "высота прыжка")
	assert_true(body.on_ground, "приземлился")
	assert_almost_eq(body.y, 0.0, 1e-9)


func test_single_jump_only() -> void:
	# Прыжок зажат всё время: в воздухе второй прыжок не срабатывает.
	var peak := 0.0
	for i in 40:
		motor.step(DT, Vector2.ZERO, true, false, false)
		peak = maxf(peak, body.y)
	assert_lt(peak, 1.26, "нет двойного прыжка")


func test_can_jump_onto_one_block_but_not_two() -> void:
	world.add_box(Vector3i(2, 0, -5), Vector3i(10, 0, 5))
	_run(60, Vector2(1, 0), true)
	_run(60, Vector2(0.3, 0))
	assert_gt(body.x, 2.0, "забрался на 1 блок")
	assert_almost_eq(body.y, 1.0, 1e-6)
	world.add_box(Vector3i(5, 1, -5), Vector3i(5, 2, 5))
	_run(90, Vector2(1, 0), true)
	assert_lt(body.x, 5.0 - body.half_width + 1e-6, "стену в 2 блока не перепрыгнуть")


func test_wall_stops_movement() -> void:
	world.add_box(Vector3i(3, 0, -5), Vector3i(3, 3, 5))
	_run(120, Vector2(1, 0))
	assert_almost_eq(body.x, 3.0 - body.half_width, 1e-6)
	assert_true(body.hit_wall)


func test_slides_along_wall() -> void:
	world.add_box(Vector3i(3, 0, -50), Vector3i(3, 3, 50))
	_run(120, Vector2(1, 1).normalized())
	assert_almost_eq(body.x, 3.0 - body.half_width, 1e-6)
	assert_gt(body.z, 3.0, "скольжение вдоль стены")


func test_crouch_does_not_fall_off_edge() -> void:
	world.floor_y = -100
	world.add_box(Vector3i(-5, -1, -5), Vector3i(1, -1, 5))
	_run(10)
	_run(300, Vector2(1, 0), false, false, true)
	assert_almost_eq(body.y, 0.0, 1e-9, "не упал")
	assert_gt(body.x, 2.0 - body.half_width - 0.05, "дошёл до края")
	assert_lt(body.x, 2.0 + body.half_width, "но не дальше края")


func test_without_crouch_falls_off_edge() -> void:
	world.floor_y = -100
	world.add_box(Vector3i(-5, -1, -5), Vector3i(1, -1, 5))
	_run(10)
	_run(120, Vector2(1, 0))
	assert_lt(body.y, -1.0)


func test_cannot_stand_up_under_low_ceiling() -> void:
	_run(5, Vector2.ZERO, false, false, true)
	world.add_box(Vector3i(-1, 1, -1), Vector3i(1, 1, 1))
	_run(5)
	assert_true(motor.crouching, "потолок на 1,6 — остаётся в приседе")
	world.solid.clear()
	_run(5)
	assert_false(motor.crouching)


func test_fall_distance_reported() -> void:
	world.floor_y = -100
	world.add_box(Vector3i(-2, 9, -2), Vector3i(2, 9, 2))
	body.set_position(0.5, 10.0, 0.5)
	_run(5)
	world.solid.clear()
	world.floor_y = 0
	var fall := 0.0
	for i in 120:
		motor.step(DT, Vector2.ZERO, false, false, false)
		if motor.landed_fall > 0.0:
			fall = motor.landed_fall
	assert_almost_eq(fall, 10.0, 0.01)


func test_world_border_is_a_wall() -> void:
	body.set_position(14999.0, 0.0, 0.5)
	_run(120, Vector2(1, 0), false, true)
	assert_almost_eq(body.x, 15000.0 - body.half_width, 1e-6)


func test_physics_identical_far_from_origin() -> void:
	# Одинаковая последовательность у начала и на 14 900 даёт одинаковое движение.
	var path_near := _record(0.5, 0.5)
	var path_far := _record(14900.5, -14900.5)
	assert_eq(path_near.size(), 270)
	for i in range(0, path_near.size(), 3):
		assert_almost_eq(path_far[i] - path_near[i], 14900.0, 1e-6, "x[%d]" % (i / 3))
		assert_almost_eq(path_far[i + 1], path_near[i + 1], 1e-9, "y[%d]" % (i / 3))
		assert_almost_eq(path_far[i + 2] - path_near[i + 2], -14901.0, 1e-6, "z[%d]" % (i / 3))


## Траектория в double: x, y, z подряд (Vector3 — float32 и сам потерял бы точность).
func _record(sx: float, sz: float) -> PackedFloat64Array:
	body.set_position(sx, 0.0, sz)
	motor.vx = 0.0
	motor.vy = 0.0
	motor.vz = 0.0
	_run(3)
	var out := PackedFloat64Array()
	for i in 90:
		motor.step(DT, Vector2(0.6, -0.8), i % 30 == 0, true, false)
		out.append_array([body.x, body.y, body.z])
	return out


func test_flying_ignores_gravity() -> void:
	motor.flying = true
	body.set_position(0.5, 20.0, 0.5)
	_run(60)
	assert_almost_eq(body.y, 20.0, 1e-6)
	_run(30, Vector2.ZERO, true)
	assert_gt(body.y, 21.0)


func test_swimming_floats_up_on_jump() -> void:
	world.floor_y = -100
	for x in range(-3, 4):
		for z in range(-3, 4):
			for y in range(-10, 1):
				world.fluid[Vector3i(x, y, z)] = true
	body.set_position(0.5, -5.0, 0.5)
	_run(60, Vector2.ZERO, true)
	assert_gt(body.y, -4.0, "всплывает")
	assert_true(motor.in_fluid)
