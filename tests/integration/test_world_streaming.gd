extends GutTest
## Мир целиком: потоковая загрузка вокруг точки, правки через действия, сохранение и
## перезагрузка, floating origin.

const ROOT := "user://test_world_streaming"

var world: World


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	if world != null:
		world.chunks.wait_all()
		world.free()
		world = null
	_cleanup()


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(ROOT):
		_rm(ROOT)


func _rm(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _make_world(save: WorldSave, seed_value: int = 4242) -> World:
	var w := World.new()
	w.setup(Registry, save, seed_value)
	w.chunks.view_distance = 3
	add_child(w)
	return w


## Крутит update(), пока область не загрузится (с таймаутом).
func _load_area(w: World, center: Vector2i, radius: int = 1) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		w.chunks.update(center)
		if w.chunks.is_area_ready(center, radius):
			return true
		OS.delay_msec(2)
	return false


## Ждёт, пока не останется задач генерации и мешинга.
func _settle(w: World, center: Vector2i) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		w.chunks.update(center)
		if w.chunks.pending_generation() == 0 and w.chunks.pending_meshing() == 0 and w.chunks.columns.size() > 0:
			w.chunks.update(center)
			if w.chunks.pending_generation() == 0 and w.chunks.pending_meshing() == 0:
				return true
		OS.delay_msec(2)
	return false


func test_streams_columns_around_center() -> void:
	world = _make_world(null)
	assert_true(_load_area(world, Vector2i.ZERO), "область загрузилась")
	assert_true(world.is_loaded(0, 0))
	assert_gt(world.chunks.mesh_node_count(), 0, "меши созданы")
	assert_gt(world.chunks.stat_quads, 0)
	# Блок совпадает с генератором напрямую.
	var h := world.generator.surface_height(5, 5)
	assert_eq(world.get_block(5, h + 1, 5) == 0 or world.is_fluid(5, h + 1, 5), true)
	assert_true(world.is_solid(5, h, 5))


func test_unloads_far_columns() -> void:
	world = _make_world(null)
	assert_true(_load_area(world, Vector2i.ZERO))
	assert_true(_load_area(world, Vector2i(40, 0)))
	assert_false(world.is_loaded(0, 0), "старая область выгружена")
	assert_lte(world.chunks.columns.size(), 60)


func test_actions_respect_rules() -> void:
	world = _make_world(null)
	assert_true(_load_area(world, Vector2i.ZERO))
	var h := world.generator.surface_height(8, 8)
	var top := Vector3i(8, h, 8)
	var granite := Registry.block_num(&"granite")
	assert_false(world.execute(GameAction.place_block(top, granite)), "в занятую клетку не ставится")
	assert_true(world.execute(GameAction.break_block(top)))
	assert_eq(world.get_block(8, h, 8), 0)
	assert_true(world.execute(GameAction.place_block(top, granite)))
	assert_eq(world.get_block(8, h, 8), granite)
	assert_false(world.execute(GameAction.break_block(Vector3i(8, -253, 8))), "материнская порода неразрушима")
	assert_false(world.execute(GameAction.place_block(Vector3i(8, 320, 8), granite)), "выше мира нельзя")
	# Нельзя поставить блок внутрь тела.
	var body := VoxelBody.new(world.is_solid)
	body.set_position(8.5, h + 1, 8.5)
	world.bodies.append(body)
	assert_false(world.execute(GameAction.place_block(Vector3i(8, h + 1, 8), granite)))


func test_edit_survives_save_and_reload() -> void:
	var save := WorldSave.create("тест", "777", &"survival", ROOT)
	world = _make_world(save, save.world_seed())
	assert_true(_load_area(world, Vector2i.ZERO))
	var h := world.generator.surface_height(3, 3)
	var log_block := Registry.block_num(&"spruce_log")
	assert_true(world.execute(GameAction.place_block(Vector3i(3, h + 1, 3), log_block)))
	assert_true(world.execute(GameAction.break_block(Vector3i(-20, world.generator.surface_height(-20, 4), 4))))
	assert_eq(world.save_chunks(), OK)
	world.chunks.wait_all()
	world.free()

	var reopened := WorldSave.open(save.folder)
	world = _make_world(reopened, reopened.world_seed())
	assert_eq(world.store.saved_column_count(), 2, "сохранены только изменённые колонны")
	assert_true(_load_area(world, Vector2i.ZERO))
	assert_eq(world.get_block(3, h + 1, 3), log_block, "правка пережила перезагрузку")
	assert_eq(world.get_block(-20, world.generator.surface_height(-20, 4), 4), 0)


func test_edit_is_remeshed() -> void:
	world = _make_world(null)
	assert_true(_settle(world, Vector2i.ZERO))
	var before := world.chunks.stat_quads
	var y := maxi(world.generator.surface_height(8, 8), world.generator.sea_level) + 5
	assert_true(world.execute(GameAction.place_block(Vector3i(8, y, 8), Registry.block_num(&"granite"))))
	assert_true(_settle(world, Vector2i.ZERO))
	assert_eq(world.chunks.stat_quads, before + 6, "одиночный блок в воздухе — 6 граней")


func test_floating_origin_far_from_center() -> void:
	world = _make_world(null)
	var wx := 14900.37
	var wz := 14900.81
	var h := world.generator.surface_height(14900, 14900)
	assert_true(world.update_origin(wx, h + 1.0, wz), "origin перенесён")
	assert_eq(world.position, -Vector3(world.origin))
	var scene := world.to_scene(wx, h + 1.0, wz)
	assert_lt(scene.length(), 32.0, "игрок рядом с началом сцены")
	# Сценовая точка в float32 хранит дробную часть точно (в отличие от 14900.37 в float32).
	assert_almost_eq(float(scene.x) + world.origin.x, wx, 1e-5)
	assert_false(world.update_origin(wx + 10.0, h + 1.0, wz), "мелкий сдвиг не переносит origin")
	assert_true(_load_area(world, Vector2i(14900 >> 4, 14900 >> 4)))
	assert_true(world.is_solid(14900, h, 14900))


func test_generation_determinism_through_world() -> void:
	world = _make_world(null, 99)
	assert_true(_load_area(world, Vector2i(2, -3)))
	var a := []
	for i in 20:
		a.append(world.get_block(32 + i, world.generator.surface_height(32 + i, -45), -45))
	world.chunks.wait_all()
	world.free()
	world = _make_world(null, 99)
	assert_true(_load_area(world, Vector2i(2, -3)))
	for i in 20:
		assert_eq(world.get_block(32 + i, world.generator.surface_height(32 + i, -45), -45), a[i])


func test_place_replaces_plant() -> void:
	world = _make_world(null)
	assert_true(_load_area(world, Vector2i.ZERO))
	var h := world.generator.surface_height(4, 4)
	var y := maxi(h, world.generator.sea_level) + 10
	var grass := Registry.block_num(&"grass")
	world.set_block(4, y, 4, grass)
	assert_true(world.execute(GameAction.place_block(Vector3i(4, y, 4), Registry.block_num(&"granite"))), "блок ставится поверх травы")
