extends GutTest

const DIR := "user://test_regions"

var store: RegionStore


func before_each() -> void:
	_cleanup()
	store = RegionStore.new(DIR, Registry)


func after_all() -> void:
	_cleanup()


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		DirAccess.remove_absolute(DIR)


func _sample_column(cpos: Vector2i) -> ChunkColumn:
	var col := TerrainGenerator.new(99, Registry).generate_column(cpos)
	col.set_block(3, 100, 4, Registry.block_num(&"spruce_log"))
	col.set_block(0, -100, 0, 0)
	return col


func _same(a: ChunkColumn, b: ChunkColumn) -> bool:
	for si in WorldConst.SECTIONS_PER_COLUMN:
		var sa := a.sections[si]
		var sb := b.sections[si]
		if (sa == null) != (sb == null):
			return false
		if sa == null:
			continue
		for i in WorldConst.SECTION_VOLUME:
			if sa.get_block(i) != sb.get_block(i):
				return false
	return true


func test_region_coordinates_negative() -> void:
	assert_eq(RegionStore.region_of(Vector2i(-1, -32)), Vector2i(-1, -1))
	assert_eq(RegionStore.region_of(Vector2i(31, -33)), Vector2i(0, -2))
	assert_eq(RegionStore.index_in_region(Vector2i(-1, 0)), 31)
	assert_eq(RegionStore.index_in_region(Vector2i(0, -1)), 31 * 32)


func test_encode_decode_roundtrip() -> void:
	var col := _sample_column(Vector2i(-3, 70))
	var back := store.decode_column(store.encode_column(col), Vector2i(-3, 70))
	assert_not_null(back)
	assert_true(_same(col, back))
	assert_true(back.from_save)


func test_unsaved_column_is_null() -> void:
	assert_null(store.load_column(Vector2i(5, 5)))
	assert_false(store.has_column(Vector2i(5, 5)))


func test_flush_and_reload_from_disk() -> void:
	var a := _sample_column(Vector2i(0, 0))
	var b := _sample_column(Vector2i(-1, -1))
	var c := _sample_column(Vector2i(31, 2))
	for col in [a, b, c]:
		store.store_column(col)
	assert_eq(store.flush(), OK)
	assert_true(FileAccess.file_exists(DIR.path_join("r.0.0.kbr")))
	assert_true(FileAccess.file_exists(DIR.path_join("r.-1.-1.kbr")))
	var fresh := RegionStore.new(DIR, Registry)
	assert_true(_same(a, fresh.load_column(Vector2i(0, 0))))
	assert_true(_same(b, fresh.load_column(Vector2i(-1, -1))))
	assert_true(_same(c, fresh.load_column(Vector2i(31, 2))))
	assert_eq(fresh.saved_column_count(), 3)


func test_compressed_size_is_small() -> void:
	var blob := store.encode_column(_sample_column(Vector2i(7, 7)))
	assert_lt(blob.size(), 20000, "zstd должен ужимать колонну в килобайты")


func test_corrupt_region_file_is_ignored() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(DIR.path_join("r.0.0.kbr"), FileAccess.WRITE)
	f.store_string("мусор")
	f.close()
	var s := RegionStore.new(DIR, Registry)
	assert_null(s.load_column(Vector2i(1, 1)))
	assert_eq(s.warnings.size(), 1)


func test_world_save_meta_roundtrip() -> void:
	var root := "user://test_world_saves"
	var ws := WorldSave.create("Мой мир: тест/1", "тайга", &"creative", root)
	assert_true(ws.folder.begins_with(root))
	assert_false(ws.folder.get_file().contains(":") or ws.folder.get_file().contains("/"), "имя папки безопасное")
	var again := WorldSave.open(ws.folder)
	assert_eq(again.meta["name"], "Мой мир: тест/1")
	assert_eq(again.world_seed(), WorldSeed.from_text("тайга"), "64-битный сид не теряется в JSON")
	assert_eq(again.meta["game_mode"], "creative")
	var second := WorldSave.create("Мой мир: тест/1", "1", &"survival", root)
	assert_ne(second.folder, ws.folder, "одноимённый мир — другая папка")
	for w in [ws, second]:
		DirAccess.remove_absolute(w.region_dir())
		DirAccess.remove_absolute(w.folder.path_join("world.json"))
		DirAccess.remove_absolute(w.folder)
	DirAccess.remove_absolute(root)
