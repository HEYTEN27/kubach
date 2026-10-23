extends GutTest


func test_dimensions() -> void:
	assert_eq(WorldConst.HEIGHT, 576)
	assert_eq(WorldConst.SECTIONS_PER_COLUMN, 36)


func test_floor_div_and_mod_negative() -> void:
	assert_eq(WorldConst.floor_div(-1, 16), -1)
	assert_eq(WorldConst.floor_div(-16, 16), -1)
	assert_eq(WorldConst.floor_div(-17, 16), -2)
	assert_eq(WorldConst.floor_div(15, 16), 0)
	assert_eq(WorldConst.floor_mod(-1, 16), 15)
	assert_eq(WorldConst.floor_mod(-16, 16), 0)
	assert_eq(WorldConst.floor_div(-1, 32), -1)


func test_block_to_column() -> void:
	assert_eq(WorldConst.block_to_column(0, 0), Vector2i(0, 0))
	assert_eq(WorldConst.block_to_column(-1, 15), Vector2i(-1, 0))
	assert_eq(WorldConst.block_to_column(-16, -17), Vector2i(-1, -2))
	assert_eq(WorldConst.block_to_column(14999, -15000), Vector2i(937, -938))


func test_section_index_bounds() -> void:
	assert_eq(WorldConst.section_index(-256), 0)
	assert_eq(WorldConst.section_index(-241), 0)
	assert_eq(WorldConst.section_index(-240), 1)
	assert_eq(WorldConst.section_index(319), 35)
	assert_eq(WorldConst.section_index(320), -1)
	assert_eq(WorldConst.section_index(-257), -1)
	assert_eq(WorldConst.section_base_y(35), 304)


func test_negative_y_local() -> void:
	# Локальная Y через & 15 корректна и для отрицательных.
	assert_eq(-1 & 15, 15)
	assert_eq(-256 & 15, 0)


func test_world_border() -> void:
	assert_true(WorldConst.is_inside_world_xz(-15000, 14999))
	assert_false(WorldConst.is_inside_world_xz(15000, 0))
	assert_false(WorldConst.is_inside_world_xz(0, -15001))
