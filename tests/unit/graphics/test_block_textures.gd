extends GutTest
## Текстуры блоков: манифест texgen покрывает все блоки, таблица для шейдера, атласы.

var bt: BlockTextures


func before_all() -> void:
	bt = BlockTextures.load_default(Registry)


func test_every_block_has_textures() -> void:
	assert_eq(bt.missing, PackedStringArray(), "все наборы textures есть в манифесте (перегенерируй tools/texgen)")


func test_variants_count() -> void:
	for name: String in bt.sets:
		var c: int = bt.sets[name]["count"]
		assert_between(c, 1, 4, name)
	assert_gt(bt.set_info("granite")["count"], 1, "у камня несколько вариантов")


func test_info_table_rows() -> void:
	var img := bt.block_info.get_image()
	assert_eq(img.get_width(), 4)
	assert_eq(img.get_height(), Registry.block_count())
	var turf := Registry.block(&"turf")
	var top: Color = img.get_pixel(0, turf.num)
	var side: Color = img.get_pixel(2, turf.num)
	assert_eq(int(top.r), bt.set_info(String(turf.texture_top))["first"])
	assert_eq(int(side.r), bt.set_info(String(turf.texture_side))["first"])
	assert_eq(side.b, 0.0, "бок дёрна не поворачивается")
	var lava := Registry.block(&"lava")
	assert_gt(img.get_pixel(0, lava.num).a, 0.0, "лава светится")
	assert_almost_eq(img.get_pixel(3, lava.num).a, BlockTextures.LIQUID_OPACITY, 0.001)


func test_atlases_are_texture_arrays() -> void:
	for t: TextureLayered in [bt.albedo, bt.normal, bt.orm]:
		assert_not_null(t)
		if t == null:
			continue
		assert_eq(t.get_width(), 128)
		assert_gte(t.get_layers(), int(JSON.parse_string(FileAccess.get_file_as_string(BlockTextures.MANIFEST))["layers"]))


func test_shared_materials() -> void:
	var m := BlockMaterials.new(bt)
	for surf: StringName in BlockMaterials.SURFACES:
		assert_not_null(m.shared[surf])
	var a := m.for_const(&"opaque", Color(0.4, 0, 0, 0))
	assert_eq(m.for_const(&"opaque", Color(0.4, 0, 0, 0)), a, "материалы с одинаковым светом переиспользуются")
	assert_eq(m.for_const(&"opaque", Color(1, 0, 0, 0)), m.shared[&"opaque"])
