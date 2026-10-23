extends GutTest

var v: SchemaValidator


func before_each() -> void:
	v = SchemaValidator.new()


func test_defaults_are_deep_copied() -> void:
	var fields := { "id": { "type": "string" }, "tags": { "type": "array", "of": { "type": "string" }, "default": [] } }
	var a := v.validate_entry({ "id": "a" }, fields, "a")
	var b := v.validate_entry({ "id": "b" }, fields, "b")
	a["tags"].append("x")
	assert_eq(b["tags"].size(), 0, "значение по умолчанию не должно быть общим")


func test_int_float_conversion() -> void:
	assert_eq(v.validate_value(3.0, { "type": "int" }, "p"), 3)
	assert_eq(typeof(v.validate_value(3.0, { "type": "int" }, "p")), TYPE_INT)
	assert_eq(v.validate_value(2, { "type": "float" }, "p"), 2.0)
	assert_eq(v.errors.size(), 0)


func test_color_and_enum() -> void:
	assert_eq(v.validate_value("#ff0000", { "type": "color" }, "p"), Color.RED)
	assert_eq(v.validate_value("a", { "type": "enum", "values": ["a", "b"] }, "p"), &"a")
	assert_eq(v.errors.size(), 0)


func test_nested_array_of_objects_paths() -> void:
	var spec := { "type": "array", "of": { "type": "object", "fields": { "n": { "type": "int", "required": true } } } }
	v.validate_value([{ "n": 1 }, {}], spec, "root")
	assert_eq(v.errors.size(), 1)
	assert_string_contains(v.errors[0], "root[1].n")


func test_ref_is_deferred() -> void:
	v.validate_value("granite", { "type": "ref", "to": ["blocks"] }, "p")
	assert_eq(v.errors.size(), 0)
	assert_eq(v.pending_refs.size(), 1)
	assert_eq(v.pending_refs[0]["id"], "granite")


func test_schema_spec_checks() -> void:
	assert_true(v.check_fields_spec({ "a": { "type": "int" } }, "s"))
	assert_false(v.check_fields_spec({ "a": { "type": "integer" } }, "s"))
	assert_false(v.check_fields_spec({ "a": { "type": "enum" } }, "s"))
	assert_false(v.check_fields_spec({ "a": { "type": "array" } }, "s"))
	assert_false(v.check_fields_spec({ "a": { "type": "ref", "to": [] } }, "s"))
	assert_false(v.check_fields_spec({ "a": { "type": "string", "pattern": "([" } }, "s"))
	assert_engine_error("missing terminating", "RegEx сам пишет ошибку компиляции шаблона")


func test_real_schemas_are_valid() -> void:
	for f in DirAccess.get_files_at("res://data/schemas"):
		var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/schemas".path_join(f)))
		assert_true(v.check_fields_spec(schema["fields"], f), "\n".join(v.errors))
