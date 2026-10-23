class_name TempDataDir
extends RefCounted
## Временный каталог data/ для тестов реестра: user://test_data/<имя>/.
## Схемы по умолчанию копируются из настоящего res://data/schemas, чтобы тесты не расходились с ними.

const ROOT := "user://test_data"

var path: String


func _init(test_name: String, copy_schemas: bool = true) -> void:
	path = ROOT.path_join(test_name)
	remove()
	DirAccess.make_dir_recursive_absolute(path)
	if copy_schemas:
		DirAccess.make_dir_recursive_absolute(path.path_join("schemas"))
		for f in DirAccess.get_files_at("res://data/schemas"):
			DirAccess.copy_absolute("res://data/schemas".path_join(f), path.path_join("schemas").path_join(f))


## Пишет JSON-файл (относительный путь внутри каталога). `data` — Variant или готовый текст.
func write(rel: String, data: Variant) -> TempDataDir:
	var full := path.path_join(rel)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var f := FileAccess.open(full, FileAccess.WRITE)
	f.store_string(data if data is String else JSON.stringify(data, "  "))
	f.close()
	return self


## Файл категории в формате реестра.
func write_entries(rel: String, entries: Array) -> TempDataDir:
	return write(rel, { "format": 1, "entries": entries })


func remove() -> void:
	if DirAccess.dir_exists_absolute(path):
		_remove_recursive(path)


## Минимальный корректный блок; поля можно перекрыть через `overrides`.
static func block(id: String, overrides: Dictionary = {}) -> Dictionary:
	var b := {
		"id": id,
		"name": { "ru": "Тест " + id, "en": "Test " + id },
		"material": "stone",
		"map_color": "#808080",
		"textures": { "all": id },
	}
	b.merge(overrides, true)
	return b


static func _remove_recursive(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_recursive(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
