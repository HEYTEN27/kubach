extends GutTest
## Реестр на настоящих данных из res://data.

var reg: ContentRegistry


func before_each() -> void:
	reg = ContentRegistry.new()
	reg.load_all()


func after_each() -> void:
	reg.free()


func test_real_data_loads_without_errors() -> void:
	assert_true(reg.loaded, "Registry.loaded")
	assert_eq(reg.errors.size(), 0, "ошибки: %s" % "\n".join(reg.errors))
	assert_eq(reg.warnings.size(), 0, "предупреждения: %s" % "\n".join(reg.warnings))


func test_block_counts() -> void:
	assert_gt(reg.get_entries("blocks").size(), 150, "этап 2: породы, руды, дерево, растения")
	assert_eq(reg.block_count(), reg.get_entries("blocks").size() + 1, "плюс воздух")


func test_shapes_and_tints() -> void:
	assert_eq(reg.block(&"grass").shape, &"cross")
	assert_false(reg.block(&"grass").opaque, "растение не закрывает соседей")
	assert_eq(reg.block(&"snow_layer").shape, &"layer")
	assert_eq(reg.block(&"turf").tint, &"grass")
	assert_eq(reg.block(&"birch_leaves").tint, &"foliage")
	assert_eq(reg.block_shape[reg.block_num(&"grass")], BlockDef.SHAPE_CROSS)


func test_air_is_zero_and_empty() -> void:
	var air := reg.block_by_num(0)
	assert_eq(air.id, &"air")
	assert_false(air.solid)
	assert_false(air.opaque)
	assert_eq(air.light_filter, 0)
	assert_eq(reg.block_num(&"air"), 0)


func test_lookup_roundtrip_for_every_block() -> void:
	for n in reg.block_count():
		var b := reg.block_by_num(n)
		assert_not_null(b)
		assert_eq(b.num, n)
		assert_eq(reg.block_num(b.id), n)
		assert_eq(reg.block(b.id), b)


func test_unknown_block_lookups() -> void:
	assert_eq(reg.block_num(&"no_such_block"), -1)
	assert_null(reg.block(&"no_such_block"))
	assert_null(reg.block_by_num(-1))
	assert_null(reg.block_by_num(reg.block_count()))


func test_flat_arrays_match_defs() -> void:
	assert_eq(reg.block_solid.size(), reg.block_count())
	for n in reg.block_count():
		var b := reg.block_by_num(n)
		assert_eq(reg.block_solid[n] == 1, b.solid, "solid %s" % b.id)
		assert_eq(reg.block_opaque[n] == 1, b.opaque, "opaque %s" % b.id)
		assert_eq(reg.block_light_emission[n], b.light_emission, "emission %s" % b.id)
		assert_eq(reg.block_light_filter[n], b.light_filter, "filter %s" % b.id)


func test_numeric_ids_follow_file_order() -> void:
	var ids: Array[StringName] = []
	for e in reg.get_entries("blocks"):
		ids.append(StringName(e["id"]))
	for i in ids.size():
		assert_eq(reg.block_num(ids[i]), i + 1)


func test_numeric_ids_deterministic_between_loads() -> void:
	var first := {}
	for n in reg.block_count():
		first[reg.block_by_num(n).id] = n
	reg.load_all()
	for id: StringName in first:
		assert_eq(reg.block_num(id), first[id])


func test_defaults_are_applied() -> void:
	var granite := reg.block(&"granite")
	assert_eq(granite.render, &"opaque")
	assert_true(granite.opaque)
	assert_true(granite.solid)
	assert_eq(granite.light_emission, 0)
	assert_eq(granite.light_filter, 15)
	assert_false(granite.flammable)
	assert_eq(granite.light_color, Color.WHITE)


func test_specific_properties() -> void:
	assert_false(reg.block(&"bedrock").is_breakable())
	assert_true(reg.block(&"granite").is_breakable())
	assert_false(reg.block(&"water").solid)
	assert_eq(reg.block(&"water").render, &"liquid")
	assert_false(reg.block(&"spruce_needles").opaque)
	assert_true(reg.block(&"spruce_log").flammable)
	assert_eq(reg.block(&"spruce_log").tool, &"axe")
	assert_true(reg.block(&"sand").has_tag("falling"))


func test_textures_resolve_all_and_faces() -> void:
	var granite := reg.block(&"granite")
	assert_eq(granite.texture_top, &"granite")
	assert_eq(granite.texture_side, &"granite")
	var turf := reg.block(&"turf")
	assert_eq(turf.texture_top, &"turf_top")
	assert_eq(turf.texture_side, &"turf_side")
	assert_eq(turf.texture_bottom, &"loam")


func test_drops_reference_and_defaults() -> void:
	var drops: Array = reg.block(&"turf").drops
	assert_eq(drops.size(), 1)
	assert_eq(drops[0]["id"], &"loam")
	assert_eq(drops[0]["min"], 1)
	assert_eq(drops[0]["chance"], 1.0)


func test_localized_names() -> void:
	var b := reg.block(&"turf")
	assert_eq(b.display_name("ru"), "Дернина")
	assert_eq(b.display_name("en"), "Turf")
	assert_eq(b.display_name("de"), "Дернина", "нет перевода — берём русский")


func test_autoload_registry_loaded() -> void:
	assert_true(Registry.loaded, "автозагрузка Registry должна загрузить data/ без ошибок")
	assert_eq(Registry.block_count(), reg.block_count())
