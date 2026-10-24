extends GutTest
## Сохранения: миграция формата, бэкапы, удаление.

const ROOT := "user://test_worlds"


func after_each() -> void:
	WorldSave.delete_world(ROOT)


func test_migrates_format_1() -> void:
	var data := { "format": 1, "name": "Старый", "seed": "5", "player": { "x": 1.0 } }
	WorldSave.migrate(data)
	assert_eq(int(data["format"]), WorldSave.META_FORMAT)
	assert_eq(data["dropped"], [])
	assert_eq(data["player"]["x"], 1.0, "данные игрока сохранились")


func test_opens_old_save() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("w"))
	var f := FileAccess.open(ROOT.path_join("w/world.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({ "format": 1, "name": "Старый", "seed": "5", "seed_text": "5", "worldgen": "normal" }))
	f.close()
	var ws := WorldSave.open(ROOT.path_join("w"))
	assert_not_null(ws, "мир этапа 1–3 открывается")
	assert_eq(int(ws.meta["format"]), WorldSave.META_FORMAT)


func test_rejects_newer_format() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("n"))
	var f := FileAccess.open(ROOT.path_join("n/world.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({ "format": 99, "name": "Будущее" }))
	f.close()
	assert_null(WorldSave.open(ROOT.path_join("n")))
	assert_push_warning("более новой версии")


func test_backup_keeps_three() -> void:
	var ws := WorldSave.create("Бэкап", "1", &"survival", ROOT)
	for i in 5:
		ws.meta["n"] = i
		ws.save_meta()
		ws.backup(3)
	var dirs := DirAccess.get_directories_at(ws.folder.path_join("backups"))
	assert_eq(dirs.size(), 3)
	var newest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ws.folder.path_join("backups/1/world.json")))
	assert_eq(int(newest["n"]), 4)
