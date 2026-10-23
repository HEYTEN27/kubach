extends GutTest

var world: FakeWorld


func before_each() -> void:
	world = FakeWorld.new()
	world.floor_y = -100


func _cast(o: Vector3, dir: Vector3, dist: float = 10.0) -> Dictionary:
	return VoxelRaycast.cast(o.x, o.y, o.z, dir, dist, world.is_solid)


func test_hits_block_ahead_with_normal() -> void:
	world.solid[Vector3i(5, 0, 0)] = true
	var r := _cast(Vector3(0.5, 0.5, 0.5), Vector3(1, 0, 0))
	assert_true(r["hit"])
	assert_eq(r["block"], Vector3i(5, 0, 0))
	assert_eq(r["normal"], Vector3i(-1, 0, 0))
	assert_almost_eq(r["distance"], 4.5, 0.0001)


func test_looking_down_hits_top_face() -> void:
	world.solid[Vector3i(-3, -2, 7)] = true
	var r := _cast(Vector3(-2.5, 1.62, 7.5), Vector3(0, -1, 0))
	assert_true(r["hit"])
	assert_eq(r["block"], Vector3i(-3, -2, 7))
	assert_eq(r["normal"], Vector3i(0, 1, 0))


func test_negative_coordinates_and_diagonal() -> void:
	world.solid[Vector3i(-4, 0, -4)] = true
	var r := _cast(Vector3(-0.5, 0.5, -0.5), Vector3(-1, 0, -1))
	assert_true(r["hit"])
	assert_eq(r["block"], Vector3i(-4, 0, -4))


func test_max_distance() -> void:
	world.solid[Vector3i(8, 0, 0)] = true
	assert_false(_cast(Vector3(0.5, 0.5, 0.5), Vector3(1, 0, 0), 5.0)["hit"])


func test_precision_far_from_origin() -> void:
	world.solid[Vector3i(14903, 70, -14900)] = true
	var r := _cast(Vector3(14900.5, 70.5, -14899.5), Vector3(1, 0, 0))
	assert_true(r["hit"])
	assert_eq(r["block"], Vector3i(14903, 70, -14900))
	assert_almost_eq(r["distance"], 2.5, 0.0001)
