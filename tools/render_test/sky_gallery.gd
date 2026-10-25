extends Node3D
## Визуальная проверка неба этапа 7: сетка кадров «время × погода» в одном PNG.
## Запуск: scripts/sky_gallery.sh [out.png]

const SHOTS := [
	["полдень, ясно", 13.0, 0.5, "clear"],
	["закат", 19.9, 0.5, "cloudy"],
	["ночь, полнолуние", 23.5, 0.5, "clear"],
	["ночь, полумесяц", 4.5, 0.3, "clear"],
	["пасмурно", 12.0, 0.5, "overcast"],
	["гроза", 15.0, 0.5, "thunderstorm"],
	["туман, утро", 7.2, 0.5, "fog"],
	["суховей", 14.0, 0.5, "dry_wind"],
	["ливень", 12.0, 0.5, "downpour"],
	["метель", 12.0, 0.5, "blizzard"],
]
const W := 480
const H := 270


func _ready() -> void:
	var out := "build/sky_gallery.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var reg: ContentRegistry = get_node("/root/Registry")
	var rig := GraphicsRig.new()
	add_child(rig)
	rig.apply({ "volumetric_fog": false, "ssao": 0, "glow": true, "auto_exposure": false, "shadow_distance": 0.0 }, null)
	rig.set_view_range(160.0, 400.0)
	var cam := Camera3D.new()
	cam.fov = 80.0
	add_child(cam)
	cam.position = Vector3(0, 2, 0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.42, 0.22)
	ground.material_override = gm
	add_child(ground)
	var fx := WeatherEffects.new()
	add_child(fx)
	fx.setup(null)
	var sim := WeatherSim.new(reg, 1)
	var grid := Image.create(W * 2, H * (SHOTS.size() / 2), false, Image.FORMAT_RGB8)
	for i in SHOTS.size():
		var s: Array = SHOTS[i]
		sim.force(StringName(s[3]))
		var w := sim.values(-10.0 if s[3] == "blizzard" else (30.0 if s[3] == "dry_wind" else 12.0))
		rig.set_weather(w)
		rig.set_sky_time(s[1], Vector2(5.5, 20.5), s[2])
		rig.move_clouds(0.0, 300.0 * i, 0.0)
		for k in 40:
			fx.update(0.05, cam.global_position, w, rig.daylight, 0.0, false)
			await get_tree().process_frame
		# Солнце на закате — на западе: смотрим туда, ночью — на юг, к луне.
		var yaw := deg_to_rad(-90.0) if s[1] > 17.0 and s[1] < 22.0 else 0.0
		cam.rotation = Vector3(deg_to_rad(16.0), yaw + PI, 0.0)
		for k in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if i == SHOTS.size() - 1:
			img.save_png(out.get_basename() + "_last.png")
		img.resize(W, H, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGB8)
		grid.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % 2) * W, (i / 2) * H))
		print("Небо: %s" % s[0])
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	grid.save_png(out)
	print("Галерея неба: %s" % out)
	get_tree().quit()
