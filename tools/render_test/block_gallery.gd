extends Node3D
## Визуальная проверка шейдеров блоков: ряд блоков на плите, солнце, камера, кадр в PNG.
## Запуск: xvfb-run godot --path . --resolution 1280x720 res://tools/render_test/block_gallery.tscn -- --out=build/gallery.png [--blocks=granite,turf]

const DEFAULT_BLOCKS := "granite,limestone,turf,oak_log,spruce_needles,birch_leaves,native_copper_ore,emerald_ore,sand,gravel,snow_block,lava,water,ice,grass,poppy,fern,moss_carpet"


func _ready() -> void:
	var out := "build/gallery.png"
	var list := DEFAULT_BLOCKS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--blocks="):
			list = a.substr(9)
	var reg: ContentRegistry = get_node("/root/Registry")
	var bt := BlockTextures.load_default(reg)
	print("albedo: ", bt.albedo, " layers ", bt.albedo.get_layers() if bt.albedo else -1, " fmt ", bt.albedo.get_format() if bt.albedo else -1, " size ", bt.albedo.get_width() if bt.albedo else -1)
	print("info turf: ", bt.block_info.get_image().get_pixel(0, reg.block_num(&"turf")), bt.block_info.get_image().get_pixel(2, reg.block_num(&"turf")))
	var mats := BlockMaterials.new(bt)
	var mesher := GreedyMesher.new(reg)
	var s := ChunkSection.new()
	var floor_block := reg.block_num(&"turf")
	for x in 16:
		for z in 6:
			s.set_block(WorldConst.local_index(x, 0, z), floor_block)
	var ids := list.split(",")
	for i in ids.size():
		var b := reg.block_num(StringName(ids[i]))
		if b <= 0:
			push_warning("нет блока %s" % ids[i])
			continue
		var x := (i % 8) * 2
		var z := 1 + (i / 8) * 2
		s.set_block(WorldConst.local_index(x, 1, z), b)
	s.analyze(reg.block_opaque, reg.block_shape)
	var res := mesher.mesh_section(GreedyMesher.snapshot(s), [null, null, null, null, null, null])
	var mesh := ArrayMesh.new()
	for surf: StringName in BlockMaterials.SURFACES:
		var arrays: Array = res.get(surf, [])
		if arrays.is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats.shared[surf])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.6, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(8, 6.5, 12.5)
	cam.rotation_degrees = Vector3(-35, 0, 0)
	cam.fov = 60
	add_child(cam)
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("Галерея: %s" % out)
	get_tree().quit()
