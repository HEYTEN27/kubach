extends RefCounted
## Полная загрузка мира вокруг игрока на дальности 12 колонн (≈450 колонн): генерация и
## мешинг во всех потоках + применение мешей. Это время «экрана загрузки» и подгрузки при полёте.

var name := "world_load_view12"
var iterations := 2
var _i := 0


func setup() -> void:
	pass


func run() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var world := World.new()
	world.setup(tree.root.get_node("/root/Registry") as ContentRegistry, null, 1000 + _i)
	world.chunks.view_distance = 12
	world.chunks.apply_budget_usec = 1000000
	tree.root.add_child(world)
	var center := Vector2i(_i * 100, 0)
	while true:
		world.chunks.update(center)
		if world.chunks.columns.size() > 400 and world.chunks.pending_generation() == 0 and world.chunks.pending_meshing() == 0:
			break
		OS.delay_msec(1)
	world.chunks.wait_all()
	world.free()
	_i += 1


func teardown() -> void:
	pass
