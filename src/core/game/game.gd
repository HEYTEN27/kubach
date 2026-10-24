extends Node3D
## Игровая сцена: окружение, мир, игрок, HUD, F3, пауза, сохранение.
## Параметры запуска — в GameLaunch.

const AUTOSAVE_SEC := 300.0
const SPAWN_READY_RADIUS := 2
const MENU_SCENE := "res://src/ui/boot/boot.tscn"

var world: World
var player: Player
var save: WorldSave
var hud: Hud
var debug_overlay: DebugOverlay
var pause_menu: PauseMenu
var rig: GraphicsRig
var grass: GrassField
var far_terrain: FarTerrain

var _loading := true
var _autosave_left := AUTOSAVE_SEC
var _play_time := 0.0
var _bench_logger: FrameTimeLogger
var _screenshot_wait := 0.0
var _climate_left := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false
	var seed_value: int
	var world_name: String
	if GameLaunch.bench_seconds > 0.0:
		world_name = "Бенчмарк"
		seed_value = WorldSeed.from_text("bench")
		save = null
	else:
		save = WorldSave.open(GameLaunch.folder) if GameLaunch.folder != "" else null
		if save == null:
			var wname := GameLaunch.new_world_name if GameLaunch.new_world_name != "" else "Новый мир"
			var s := GameLaunch.seed_text if GameLaunch.seed_text != "" else str(WorldSeed.random())
			save = WorldSave.create(wname, s, GameLaunch.game_mode, WorldSave.ROOT, WorldGenSettings.from_dict(GameLaunch.settings))
		world_name = save.meta["name"]
		seed_value = save.world_seed()

	if GameLaunch.preset != "":
		Settings.set_preset(StringName(GameLaunch.preset))
	rig = GraphicsRig.new()
	add_child(rig)
	world = World.new()
	world.name = "World"
	world.setup(Registry, save, seed_value, save.gen_settings() if save else WorldGenSettings.new())
	world.chunks.view_distance = GameLaunch.view_distance if GameLaunch.view_distance > 0 else int(Settings.graphics.get("view_distance", 12))
	if save != null:
		world.game_mode = StringName(save.meta.get("game_mode", "survival"))
		_play_time = float(save.meta.get("play_time_sec", 0.0))
	else:
		world.game_mode = &"creative"
	add_child(world)
	grass = GrassField.new()
	grass.name = "Grass"
	world.add_child(grass)
	grass.setup(world.chunks, world.chunks.materials.textures)
	far_terrain = FarTerrain.new()
	far_terrain.name = "FarTerrain"
	world.add_child(far_terrain)
	far_terrain.setup(world, world.chunks.season)
	_apply_graphics(Settings.graphics)
	Settings.graphics_changed.connect(_apply_graphics)
	if GameLaunch.screenshot_path != "":
		# Программный OpenGL рисует кадр секундами: пока мир грузится, не рисуем его и
		# применяем готовые меши без бюджета.
		world.visible = false
		world.chunks.apply_budget_usec = 200000
		world.chunks.max_mesh_in_flight = 256
		world.chunks.max_light_in_flight = 32
		world.chunks.max_gen_in_flight = 16

	player = Player.new()
	player.name = "Player"
	var spawn := _spawn_point()
	player.setup(world, spawn[0], spawn[1], spawn[2], spawn[3], spawn[4])
	add_child(player)
	player.teleport(spawn[0], spawn[1], spawn[2])
	if save != null and save.meta.get("player", {}).get("flying", false):
		player.motor.flying = true
	if GameLaunch.camera != "":
		player.set_camera_mode({ "first": Player.CameraMode.FIRST_PERSON, "back": Player.CameraMode.THIRD_BACK,
			"front": Player.CameraMode.THIRD_FRONT }.get(GameLaunch.camera, Player.CameraMode.FIRST_PERSON))

	var border := WorldBorder.new()
	border.world = world
	border.player = player
	add_child(border)

	hud = Hud.new()
	hud.player = player
	hud.world = world
	add_child(hud)
	hud.set_loading(true, "Загрузка мира…")
	debug_overlay = DebugOverlay.new()
	debug_overlay.player = player
	debug_overlay.world = world
	debug_overlay.world_name = world_name
	add_child(debug_overlay)
	debug_overlay.visible = GameLaunch.show_debug
	pause_menu = PauseMenu.new()
	pause_menu.resume_requested.connect(_resume)
	pause_menu.save_requested.connect(func() -> void:
		save_game()
		hud.show_toast("Мир сохранён"))
	pause_menu.quit_to_menu_requested.connect(func() -> void:
		save_game()
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE))
	pause_menu.quit_game_requested.connect(_quit)
	add_child(pause_menu)


func _process(delta: float) -> void:
	var b := player.body
	var center := Vector2i(floori(b.x) >> 4, floori(b.z) >> 4)
	world.chunks.update(center)
	grass.update(center)
	far_terrain.update(b.x, b.z)
	_climate_left -= delta
	if _climate_left <= 0.0:
		_climate_left = 0.5
		var bi := world.biome_at(floori(b.x), floori(b.z))
		if bi >= 0:
			rig.set_biome_climate(world.generator.biomes.temperature_c[bi])
	if _loading:
		if GameLaunch.screenshot_path != "":
			_screenshot_wait += delta
			if _screenshot_wait > 5.0:
				_screenshot_wait = 0.0
				print("Загрузка: колонн %d, генерация %d, свет %d, мешинг %d" % [world.chunks.columns.size(),
					world.chunks.pending_generation(), world.chunks.pending_lighting(), world.chunks.pending_meshing()])
		if world.chunks.is_area_ready(center, SPAWN_READY_RADIUS):
			_on_loaded()
		else:
			var total := (SPAWN_READY_RADIUS * 2 + 1) * (SPAWN_READY_RADIUS * 2 + 1)
			var ready := 0
			for dz in range(-SPAWN_READY_RADIUS, SPAWN_READY_RADIUS + 1):
				for dx in range(-SPAWN_READY_RADIUS, SPAWN_READY_RADIUS + 1):
					if world.chunks.columns.has(center + Vector2i(dx, dz)):
						ready += 1
			hud.set_loading(true, "Загрузка мира… %d%%" % (100 * ready / total))
		return
	_play_time += delta
	if save != null:
		_autosave_left -= delta
		if _autosave_left <= 0.0:
			save_game()
			hud.show_toast("Автосохранение")
	if GameLaunch.bench_seconds > 0.0:
		_bench_fly()
	if GameLaunch.screenshot_path != "":
		_screenshot_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _loading:
		return
	if event.is_action_pressed(&"pause"):
		_pause()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_game_mode"):
		world.game_mode = &"survival" if world.game_mode == &"creative" else &"creative"
		hud.show_toast("Режим: %s" % ("творческий" if world.game_mode == &"creative" else "выживание"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _loading and not get_tree().paused and GameLaunch.bench_seconds == 0.0 and GameLaunch.screenshot_path == "":
		_pause()


func save_game() -> void:
	if save == null:
		return
	var b := player.body
	save.meta["player"] = { "x": b.x, "y": b.y, "z": b.z, "yaw": player.yaw, "pitch": player.pitch, "flying": player.motor.flying }
	save.meta["game_mode"] = String(world.game_mode)
	save.meta["play_time_sec"] = _play_time
	var err := world.save_chunks()
	if err != OK:
		push_error("Сохранение region-файлов: %s" % error_string(err))
	save.save_meta()
	_autosave_left = AUTOSAVE_SEC
	EventBus.world_saved.emit(save.folder)


func _on_loaded() -> void:
	_loading = false
	_screenshot_wait = 0.0
	hud.set_loading(false)
	# В режиме скриншота игрок заморожен — кадр повторяем.
	player.active = GameLaunch.screenshot_path == ""
	if GameLaunch.screenshot_path == "" and GameLaunch.bench_seconds == 0.0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if GameLaunch.bench_seconds > 0.0:
		player.motor.flying = true
		_bench_logger = FrameTimeLogger.new()
		_bench_logger.label = "flight_%s_view%d" % [Settings.preset, world.chunks.view_distance]
		_bench_logger.duration_sec = GameLaunch.bench_seconds
		_bench_logger.finished.connect(func(_s: Dictionary) -> void: _quit())
		add_child(_bench_logger)


func _pause() -> void:
	get_tree().paused = true
	pause_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	get_tree().paused = false
	pause_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit() -> void:
	save_game()
	world.chunks.wait_all()
	grass.wait_all()
	far_terrain.wait_all()
	get_tree().quit()


## [x, y, z, yaw, pitch] — из сохранения, из аргументов или поиск суши у начала мира.
func _spawn_point() -> Array:
	var yaw := 0.0
	var pitch := 0.0
	var p: Dictionary = save.meta.get("player", {}) if save != null else {}
	var out: Array
	if not p.is_empty():
		yaw = p.get("yaw", 0.0)
		pitch = p.get("pitch", 0.0)
		out = [float(p["x"]), float(p["y"]), float(p["z"])]
	else:
		out = _find_land()
	if GameLaunch.teleport.size() == 3:
		out = [GameLaunch.teleport[0], GameLaunch.teleport[1], GameLaunch.teleport[2]]
		if is_nan(out[1]):
			out[1] = float(maxi(world.generator.surface_height(floori(out[0]), floori(out[2])), world.generator.sea_level) + 1)
	if GameLaunch.look.x != INF:
		yaw = deg_to_rad(GameLaunch.look.x)
		pitch = deg_to_rad(GameLaunch.look.y)
	if GameLaunch.bench_seconds > 0.0:
		# Маршрут бенчмарка начинается в тайге (самый тяжёлый лес) и идёт на восток.
		var taiga := _find_biome(&"taiga")
		out = [taiga.x + 0.5, float(world.generator.surface_height(taiga.x, taiga.y)), taiga.y + 0.5]
		out[1] = maxf(out[1], float(world.generator.sea_level)) + 28.0
		pitch = deg_to_rad(-12.0)
		yaw = -PI * 0.5
	return out + [yaw, pitch]


func _find_biome(id: StringName) -> Vector2i:
	var gen := world.generator
	var b := gen.biomes.index_of(id)
	for r in range(0, 8000, 64):
		for i in maxi(1, r / 16):
			var a := TAU * i / maxi(1, r / 16)
			var x := roundi(cos(a) * r)
			var z := roundi(sin(a) * r)
			if gen.grid_biome(x, z) == b:
				return Vector2i(x, z)
	return Vector2i.ZERO


## Ближайшая к началу мира суша (спираль с шагом 16 блоков).
func _find_land() -> Array:
	var gen := world.generator
	for r in range(0, 128):
		for i in maxi(1, r * 8):
			var a := TAU * i / maxi(1, r * 8)
			var x := roundi(cos(a) * r * 16.0)
			var z := roundi(sin(a) * r * 16.0)
			var h := gen.surface_height(x, z)
			if h > gen.sea_level and h < gen.sea_level + 40:
				return [x + 0.5, float(h + 1), z + 0.5]
	return [0.5, float(gen.surface_height(0, 0) + 1), 0.5]


## Настройки графики: окружение, дальность, трава, LOD.
func _apply_graphics(g: Dictionary) -> void:
	rig.apply(g, get_viewport())
	var ch := world.chunks
	if GameLaunch.view_distance <= 0:
		ch.set_view_distance(int(g.get("view_distance", 12)))
	var view := ch.view_distance
	var lod: int = g.get("lod_distance", 32)
	far_terrain.configure(lod > view, lod, (view - 1.5) * 16.0)
	grass.configure(g.get("dense_grass", true), int(g.get("grass_distance", 3)), int(g.get("grass_density", 4)))
	ch.materials.set_param(&"parallax", g.get("parallax", false))
	rig.set_view_range(view * 16.0, (lod if lod > view else view) * 16.0)


## Бенчмарк: прямой полёт на восток с постоянной скоростью.
func _bench_fly() -> void:
	var b := player.body
	var dt := get_process_delta_time()
	b.x += PlayerMotor.FLY_SPEED * dt
	var ground := float(maxi(world.generator.surface_height(floori(b.x + 32.0), floori(b.z)), world.generator.sea_level))
	b.y = lerpf(b.y, ground + 28.0, 0.02)
	player.motor.vx = 0.0
	player.motor.vy = 0.0


## Скриншот: ждём, пока догрузится вся дальность (не дольше 60 с), затем ещё несколько кадров.
func _screenshot_step(delta: float) -> void:
	_screenshot_wait += delta
	var ch := world.chunks
	var settled := ch.pending_generation() == 0 and ch.pending_meshing() == 0 and grass.pending() == 0 \
			and far_terrain.pending() == 0
	if not settled and _screenshot_wait < 60.0:
		return
	if _screenshot_wait < 0.0:
		return
	_screenshot_wait = -1000.0
	world.visible = true
	for i in 8:
		await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(GameLaunch.screenshot_path)
	print("Скриншот: %s (%s), колонн %d, граней %d" % [GameLaunch.screenshot_path, error_string(err), ch.columns.size(), ch.stat_quads])
	world.chunks.wait_all()
	get_tree().quit(0 if err == OK else 1)
