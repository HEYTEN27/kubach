extends GutTest


func test_uniform_until_written() -> void:
	var s := ChunkSection.filled(3)
	assert_true(s.is_uniform())
	assert_eq(s.get_block(1234), 3)
	s.set_block(1234, 3)
	assert_true(s.is_uniform(), "запись того же блока не разворачивает секцию")
	assert_eq(s.version, 0)


func test_expand_and_compact() -> void:
	var s := ChunkSection.filled(3)
	s.set_block(10, 5)
	assert_false(s.is_uniform())
	assert_eq(s.get_block(10), 5)
	assert_eq(s.get_block(11), 3)
	assert_eq(s.version, 1)
	assert_false(s.try_compact())
	s.set_block(10, 3)
	assert_true(s.try_compact())
	assert_eq(s.uniform, 3)


func test_snapshot_is_copy_on_write() -> void:
	var s := ChunkSection.filled(1)
	s.set_block(0, 2)
	var snap := s.blocks
	s.set_block(0, 7)
	assert_eq(snap[0], 2, "снимок для потока не должен меняться")
	assert_eq(s.get_block(0), 7)


func test_column_set_get_and_empty_sections() -> void:
	var c := ChunkColumn.new(Vector2i(2, -3))
	assert_eq(c.get_block(0, 100, 0), 0)
	assert_true(c.set_block(5, -200, 7, 4))
	assert_eq(c.get_block(5, -200, 7), 4)
	assert_eq(c.top_block_y(5, 7), -200)
	assert_true(c.set_block(5, -200, 7, 0))
	assert_null(c.sections[WorldConst.section_index(-200)], "опустевшая секция удаляется")
	assert_false(c.set_block(0, 320, 0, 1))
