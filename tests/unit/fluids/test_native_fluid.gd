extends GutTest
## Нативный автомат жидкостей (C++) обязан давать тот же мир, что GDScript-версия.

var stone: int


func before_all() -> void:
	stone = Registry.block_num(&"granite")


func _make_world() -> World:
	var w := World.new()
	w.setup(Registry, null, 21)
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var col := ChunkColumn.new(Vector2i(cx, cz))
			for z in 16:
				for x in 16:
					col.set_block(x, 60, z, stone)
			w.chunks.columns[Vector2i(cx, cz)] = col
	var wf := Registry.fluid_ids.find(&"water")
	var full := Registry.fluid_level_blocks[wf][8]
	# Бассейн на постаменте (прорыв плотины), яма, источник, лава, огонь.
	for z in range(0, 6):
		for x in range(0, 6):
			for y in range(61, 63):
				w.set_block(x, y, z, stone)
			for y in range(63, 66):
				w.set_block(x, y, z, full)
	for z in range(-8, -4):
		for x in range(-8, -4):
			w.set_block(x, 60, z, 0)
	w.set_block(-9, 61, -6, Registry.block_num(&"water"))
	w.set_block(8, 61, 2, Registry.block_num(&"lava"))
	w.set_block(-3, 61, 4, Registry.block_num(&"fire"))
	return w


func _start(sim: FluidSim) -> void:
	for z in range(0, 6):
		for x in range(0, 6):
			for y in range(63, 66):
				sim.wake(Vector3i(x, y, z))
	sim.wake(Vector3i(-9, 61, -6))


func test_native_matches_gdscript() -> void:
	if not ClassDB.class_exists(&"NativeFluid"):
		fail_test("нет нативной библиотеки")
		return
	var wa := _make_world()
	var wb := _make_world()
	var sa := FluidSim.new(wa, Registry, false)
	var sb := FluidSim.new(wb, Registry, true)
	assert_null(sa.native)
	assert_not_null(sb.native, "для World берётся C++")
	_start(sa)
	_start(sb)
	for i in 60:
		var ca := sa.step()
		var cb := sb.step()
		assert_eq(cb, ca, "шаг %d: число изменений" % i)
		if ca != cb:
			break
	var diffs := 0
	for y in range(58, 70):
		for z in range(-16, 32):
			for x in range(-16, 32):
				if wa.get_block(x, y, z) != wb.get_block(x, y, z):
					diffs += 1
	assert_eq(diffs, 0, "мир совпадает клетка в клетку")
	assert_eq(sb.active_cells(), sa.active_cells(), "активные клетки совпадают по порядку")
	assert_eq(sb.sleeping_count(), sa.sleeping_count())
	wa.free()
	wb.free()


func test_native_is_faster() -> void:
	if not ClassDB.class_exists(&"NativeFluid"):
		fail_test("нет нативной библиотеки")
		return
	var wa := _make_world()
	var wb := _make_world()
	var sa := FluidSim.new(wa, Registry, false)
	var sb := FluidSim.new(wb, Registry, true)
	_start(sa)
	_start(sb)
	var t0 := Time.get_ticks_usec()
	for i in 10:
		sa.step()
	var t_gd := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in 10:
		sb.step()
	var t_c := Time.get_ticks_usec() - t0
	gut.p("шаг воды: GDScript %.2f мс, C++ %.2f мс" % [t_gd / 10000.0, t_c / 10000.0])
	assert_lt(t_c * 4, t_gd, "C++ заметно быстрее")
	wa.free()
	wb.free()
