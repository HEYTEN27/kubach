extends GutTest
## Реестр на временных каталогах: ошибки данных должны ловиться с понятным сообщением.

var reg: ContentRegistry
var dir: TempDataDir


func before_each() -> void:
	reg = ContentRegistry.new()


func after_each() -> void:
	reg.free()
	if dir:
		dir.remove()
		dir = null


func _load(test_name: String, entries: Array) -> bool:
	dir = TempDataDir.new(test_name)
	dir.write_entries("blocks.json", entries)
	return reg.load_all(dir.path)


func _errors_text() -> String:
	return "\n".join(reg.errors)


func test_minimal_valid_block_loads() -> void:
	assert_true(_load("minimal", [TempDataDir.block("rock")]), _errors_text())
	assert_eq(reg.block_num(&"rock"), 1)


func test_missing_data_dir() -> void:
	assert_false(reg.load_all("user://test_data/does_not_exist"))
	assert_string_contains(_errors_text(), "не найден")


func test_broken_json_reports_line() -> void:
	dir = TempDataDir.new("broken_json")
	dir.write("blocks.json", '{\n  "format": 1,\n  "entries": [ { "id": "a", } \n')
	assert_false(reg.load_all(dir.path))
	assert_string_contains(_errors_text(), "ошибка JSON")
	assert_string_contains(_errors_text(), "blocks.json:")


func test_wrong_format_version() -> void:
	dir = TempDataDir.new("format")
	dir.write("blocks.json", { "format": 99, "entries": [] })
	assert_false(reg.load_all(dir.path))
	assert_string_contains(_errors_text(), "format")


func test_missing_required_field() -> void:
	var b := TempDataDir.block("rock")
	b.erase("material")
	assert_false(_load("required", [b]))
	assert_string_contains(_errors_text(), "rock.material: обязательное поле")
	assert_eq(reg.block_num(&"rock"), -1, "битый блок не должен попасть в реестр")


func test_wrong_type() -> void:
	assert_false(_load("type", [TempDataDir.block("rock", { "hardness": "твёрдый" })]))
	assert_string_contains(_errors_text(), "rock.hardness: ожидалось число")


func test_int_rejects_fraction() -> void:
	assert_false(_load("int", [TempDataDir.block("rock", { "light_emission": 2.5 })]))
	assert_string_contains(_errors_text(), "целое")


func test_range_check() -> void:
	assert_false(_load("range", [TempDataDir.block("rock", { "light_emission": 16 })]))
	assert_string_contains(_errors_text(), "больше максимума")


func test_bad_enum() -> void:
	assert_false(_load("enum", [TempDataDir.block("rock", { "material": "plasma" })]))
	assert_string_contains(_errors_text(), "'plasma' не входит")


func test_unknown_field() -> void:
	assert_false(_load("unknown", [TempDataDir.block("rock", { "colour": "#fff" })]))
	assert_string_contains(_errors_text(), "неизвестное поле 'colour'")


func test_missing_translation() -> void:
	assert_false(_load("i18n", [TempDataDir.block("rock", { "name": { "ru": "Скала" } })]))
	assert_string_contains(_errors_text(), "нет перевода 'en'")


func test_bad_color() -> void:
	assert_false(_load("color", [TempDataDir.block("rock", { "map_color": "серый" })]))
	assert_string_contains(_errors_text(), "цвет")


func test_bad_id_pattern() -> void:
	assert_false(_load("id", [TempDataDir.block("Rock-1")]))
	assert_string_contains(_errors_text(), "шаблону")


func test_air_is_reserved() -> void:
	assert_false(_load("air", [TempDataDir.block("air")]))
	assert_string_contains(_errors_text(), "зарезервирован")


func test_partial_textures_rejected() -> void:
	assert_false(_load("tex", [TempDataDir.block("rock", { "textures": { "top": "rock_top" } })]))
	assert_string_contains(_errors_text(), "textures")


func test_dangling_drop_reference() -> void:
	assert_false(_load("ref", [TempDataDir.block("rock", { "drops": [{ "id": "diamond" }] })]))
	assert_string_contains(_errors_text(), "несуществующий id 'diamond'")


func test_drop_reference_to_later_block_is_ok() -> void:
	var ok := _load("ref_ok", [
		TempDataDir.block("ore", { "drops": [{ "id": "nugget" }] }),
		TempDataDir.block("nugget"),
	])
	assert_true(ok, _errors_text())


func test_drop_min_greater_than_max() -> void:
	assert_false(_load("minmax", [TempDataDir.block("rock", { "drops": [{ "id": "rock", "min": 3, "max": 1 }] })]))
	assert_string_contains(_errors_text(), "min больше max")


func test_duplicate_id_in_same_file() -> void:
	assert_false(_load("dup", [TempDataDir.block("rock"), TempDataDir.block("rock")]))
	assert_string_contains(_errors_text(), "дубликат id 'rock'")


func test_extension_files_load_after_base_in_order() -> void:
	dir = TempDataDir.new("ext")
	dir.write_entries("blocks.json", [TempDataDir.block("base")])
	dir.write_entries("blocks/b_more.json", [TempDataDir.block("second")])
	dir.write_entries("blocks/a_first.json", [TempDataDir.block("first")])
	assert_true(reg.load_all(dir.path), _errors_text())
	assert_eq(reg.block_num(&"base"), 1)
	assert_eq(reg.block_num(&"first"), 2)
	assert_eq(reg.block_num(&"second"), 3)


func test_duplicate_across_files_names_both() -> void:
	dir = TempDataDir.new("dup_files")
	dir.write_entries("blocks.json", [TempDataDir.block("rock")])
	dir.write_entries("blocks/mod.json", [TempDataDir.block("rock")])
	assert_false(reg.load_all(dir.path))
	assert_string_contains(_errors_text(), "mod.json")
	assert_string_contains(_errors_text(), "уже объявлен в")


func test_category_without_schema_loads_with_warning() -> void:
	dir = TempDataDir.new("noschema")
	dir.write_entries("blocks.json", [TempDataDir.block("rock")])
	dir.write_entries("widgets.json", [{ "id": "gear", "teeth": 12 }])
	assert_true(reg.load_all(dir.path), _errors_text())
	assert_eq(reg.warnings.size(), 1)
	assert_eq(reg.get_entry("widgets", &"gear")["teeth"], 12.0)
	assert_eq(reg.categories(), PackedStringArray(["blocks", "widgets"]))


func test_blocks_without_schema_is_error() -> void:
	dir = TempDataDir.new("noblockschema", false)
	dir.write_entries("blocks.json", [TempDataDir.block("rock")])
	assert_false(reg.load_all(dir.path))
	assert_eq(reg.block_count(), 1, "остаётся только воздух")


func test_reload_clears_previous_state() -> void:
	assert_true(_load("reload_a", [TempDataDir.block("rock")]))
	dir.remove()
	assert_true(_load("reload_b", [TempDataDir.block("sand")]))
	assert_eq(reg.block_num(&"rock"), -1)
	assert_eq(reg.block_num(&"sand"), 1)
	assert_eq(reg.block_solid.size(), 2)
