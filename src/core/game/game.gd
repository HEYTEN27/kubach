extends Node3D
## Игровая сцена: окружение, мир, игрок, инвентарь, выживание, HUD, окна, F3, пауза, сохранение.
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
var dropped: DroppedItems
var survival: SurvivalController
var stations: StationSystem
var crafting: CraftingController
## Операции окна инвентаря (курсор, клики) — исполнитель действий InventoryAction.
var inv_ops: InventoryOps
var _window: InventoryWindow
var _status: StatusScreen
var _station_pos := Vector3i(0, -10000, 0)
var _death: DeathScreen
## Точка мира для возрождения без кровати: [x, y, z].
var _world_spawn: Array = []

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
	var pmeta: Dictionary = save.meta.get("player", {}) if save != null else {}
	player.appearance = pmeta.get("appearance", GameLaunch.appearance if not GameLaunch.appearance.is_empty() else CharacterModel.default_appearance())
	player.setup(world, spawn[0], spawn[1], spawn[2], spawn[3], spawn[4])
	if pmeta.has("inventory"):
		player.inventory.from_dict(pmeta["inventory"])
	else:
		_starting_inventory()
	add_child(player)
	inv_ops = InventoryOps.new(player.inventory)
	inv_ops.creative = world.game_mode == &"creative"
	inv_ops.dropped.connect(_throw_from_player)
	player.interaction.container_requested.connect(open_container)
	player.interaction.tool_broken.connect(func(id: StringName) -> void:
		hud.show_toast("Сломался инструмент: %s" % Registry.item(id).display_name()))
	dropped = DroppedItems.new()
	dropped.name = "DroppedItems"
	world.add_child(dropped)
	dropped.setup(world)
	dropped.inventory = player.inventory
	dropped.player_body = player.body
	dropped.picked_up.connect(func(_s: ItemStack) -> void: Audio.play_ui("ui/pickup"))
	if save != null:
		dropped.from_array(save.meta.get("dropped", []))
	_setup_survival(pmeta, spawn)
	_setup_crafting(pmeta)
	_apply_player_settings()
	Settings.setting_changed.connect(func(_id: String, _v: Variant) -> void: _apply_player_settings())
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
	hud.survival = survival
	add_child(hud)
	survival.hurt.connect(func(amount: float, _c: String) -> void: hud.vitals_hud.flash_hurt(amount))
	survival.message.connect(func(t: String) -> void: hud.show_toast(t))
	crafting.message.connect(func(t: String) -> void: hud.show_toast(t, 3.5))
	survival.effect_changed.connect(_on_effect_changed)
	if save != null and save.meta.get("hardcore_dead", false):
		hud.show_toast("Хардкор: персонаж погиб — мир открыт только для осмотра", 6.0)
	hud.set_loading(true, "Загрузка мира…")
	debug_overlay = DebugOverlay.new()
	debug_overlay.player = player
	debug_overlay.world = world
	debug_overlay.world_name = world_name
	debug_overlay.survival = survival
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
	rig.set_time_of_day(survival.clock.hour())
	stations.viewer = Vector3(b.x, b.y, b.z)
	survival.daylight = rig.daylight
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
			save_game(true)
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
	elif event.is_action_pressed(&"inventory") and _window == null and _status == null and _death == null and not get_tree().paused:
		open_inventory()
	elif event.is_action_pressed(&"stats") and _window == null and _status == null and _death == null and not get_tree().paused:
		_open_status()
	elif event.is_action_pressed(&"drop_item") and _window == null and player.input_allowed():
		var a := InventoryAction.make(InventoryAction.Op.DROP_SLOT, "hotbar", player.inventory.selected)
		a.amount = 0 if Input.is_key_pressed(KEY_CTRL) else 1
		execute_inventory(a)
	elif event.is_action_pressed(&"swap_hands") and _window == null:
		var eq := player.inventory.equipment
		var held := player.inventory.held()
		if eq.accepts(PlayerInventory.OFFHAND_SLOT, held):
			var off := eq.get_stack(PlayerInventory.OFFHAND_SLOT)
			eq.set_stack(PlayerInventory.OFFHAND_SLOT, held)
			player.inventory.hotbar.set_stack(player.inventory.selected, off)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_game_mode"):
		world.game_mode = &"survival" if world.game_mode == &"creative" else &"creative"
		inv_ops.creative = world.game_mode == &"creative"
		hud.show_toast("Режим: %s" % ("творческий" if world.game_mode == &"creative" else "выживание"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _loading and not get_tree().paused and GameLaunch.bench_seconds == 0.0 and GameLaunch.screenshot_path == "":
		_pause()


## autosave — перед записью сохранить копию предыдущего состояния (3 последних, раздел 21).
func save_game(autosave: bool = false) -> void:
	if save == null:
		return
	if autosave:
		save.backup(3)
	var b := player.body
	save.meta["player"] = { "x": b.x, "y": b.y, "z": b.z, "yaw": player.yaw, "pitch": player.pitch, "flying": player.motor.flying,
		"inventory": player.inventory.to_dict(), "appearance": player.appearance, "survival": survival.to_dict(),
		"recipes": crafting.to_dict() }
	save.meta["dropped"] = dropped.to_array()
	save.meta["season"] = String(survival.clock.season())
	save.meta["day"] = survival.clock.day
	save.meta["world_spawn"] = _world_spawn
	save.meta["worldgen"] = world.settings.to_dict()
	save.meta["game_mode"] = String(world.game_mode)
	save.meta["play_time_sec"] = _play_time
	stations.flush_all()
	var err := world.save_chunks()
	if err != OK:
		push_error("Сохранение region-файлов: %s" % error_string(err))
	save.save_meta()
	_save_preview()
	_autosave_left = float(Settings.get_value("autosave_minutes")) * 60.0
	EventBus.world_saved.emit(save.folder)


## Превью слота: уменьшенный текущий кадр (без окон поверх — их на время скрываем нельзя,
## поэтому берём кадр как есть).
func _save_preview() -> void:
	if DisplayServer.get_name() == "headless" or _loading:
		return
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	img.save_png(save.folder.path_join("preview.png"))


## Новый мир: стартовая одежда из редактора персонажа; в выживании — стартовый набор,
## в творческом — блоки в хотбаре.
func _starting_inventory() -> void:
	var inv := player.inventory
	var outfit: Array = GameLaunch.outfit if not GameLaunch.outfit.is_empty() else [
		{ "id": "linen_shirt" }, { "id": "linen_pants" }, { "id": "bast_shoes" }]
	for o: Dictionary in outfit:
		var d := Registry.item(StringName(o.get("id", "")))
		if d == null:
			continue
		var st := ItemStack.create(d)
		if o.has("color"):
			st.data["color"] = o["color"]
		var slot := PlayerInventory.EQUIP_KINDS.find(d.equip)
		if slot >= 0 and inv.equipment.get_stack(slot) == null:
			inv.equipment.set_stack(slot, st)
		else:
			inv.add(st)
	if world.game_mode == &"survival":
		# Стартовый набор до ремесла (этап 6): спальник, костёр, хлеб, бинты.
		for pair: Array in [[&"sleeping_bag", 1], [&"campfire", 1], [&"rye_bread", 3], [&"bandage", 2], [&"flint", 3],
				[&"plant_fiber", 6]]:
			var d := Registry.item(pair[0])
			if d != null:
				inv.add(ItemStack.create(d, pair[1]))
	if world.game_mode == &"creative":
		var i := 0
		for id: StringName in [&"granite", &"spruce_log", &"loam", &"sand", &"chest_wood", &"torch", &"oak_leaves",
				&"iron_pickaxe", &"iron_axe"]:
			var d := Registry.item(id)
			if d != null:
				inv.hotbar.set_stack(i, ItemStack.create(d, d.stack))
				i += 1


## Настройки, которые читает игрок: обзор, мышь, присед/бег, автопрыжок, вес, автосохранение.
func _apply_player_settings() -> void:
	if stations != null:
		var auto := String(Settings.get_value("minigames")) == "auto"
		stations.set_auto(auto)
		crafting.minigames = not auto
		stations.particles_level = { "low": 1, "medium": 2, "high": 2 }.get(String(Settings.get_value("particles")), 2)
	player.fov = float(Settings.get_value("fov"))
	player.mouse_sens_x = 0.0025 * float(Settings.get_value("mouse_sens_x")) * (-1.0 if Settings.get_value("invert_x") else 1.0)
	player.mouse_sens_y = 0.0025 * float(Settings.get_value("mouse_sens_y")) * (-1.0 if Settings.get_value("invert_y") else 1.0)
	player.crouch_toggle = String(Settings.get_value("crouch_mode")) == "toggle"
	player.sprint_toggle = String(Settings.get_value("sprint_mode")) == "toggle"
	player.auto_jump = bool(Settings.get_value("auto_jump"))
	player.camera_bob = bool(Settings.get_value("camera_bob"))
	player.pad_look_speed = float(Settings.get_value("pad_look_speed"))
	player.use_weight = bool(Settings.get_value("weight"))
	rig.set_depth_of_field(bool(Settings.get_value("depth_of_field")))
	var v := survival.vitals
	v.diseases_enabled = bool(Settings.get_value("diseases"))
	v.temperature_enabled = bool(Settings.get_value("body_temperature"))
	v.thirst_enabled = bool(Settings.get_value("thirst"))
	# Сложность — у мира; настройка меняет её для текущего мира (кроме хардкора).
	var diff := StringName(Settings.get_value("difficulty"))
	if world.settings.difficulty != &"hardcore" and diff != world.settings.difficulty and save != null:
		world.settings.difficulty = diff
		survival.set_difficulty(diff)
		if hud != null:
				hud.show_toast("Сложность мира: %s" % Registry.get_entry("difficulties", diff)["name"]["ru"])
	_autosave_left = minf(_autosave_left, float(Settings.get_value("autosave_minutes")) * 60.0)


## Выживание: часы по длине суток мира, сложность, сохранённое состояние, точки возрождения.
func _setup_survival(pmeta: Dictionary, spawn: Array) -> void:
	survival = SurvivalController.new()
	survival.name = "Survival"
	survival.setup(world, player, float(world.settings.day_length))
	survival.set_difficulty(world.settings.difficulty)
	if pmeta.has("survival"):
		survival.from_dict(pmeta["survival"])
	if GameLaunch.start_hour >= 0.0:
		survival.clock.minute = GameLaunch.start_hour * 60.0
	add_child(survival)
	var ws: Array = save.meta.get("world_spawn", []) if save != null else []
	_world_spawn = ws if ws.size() == 3 else [spawn[0], spawn[1], spawn[2]]
	if world.settings.difficulty != &"hardcore" and save != null:
		Settings.set_value("difficulty", String(world.settings.difficulty))
	if save != null and save.meta.get("hardcore_dead", false):
		world.game_mode = &"creative"
	survival.died.connect(_on_died)
	player.interaction.bed_requested.connect(func(pos: Vector3i) -> void:
		var msg := survival.use_bed(pos)
		if msg.contains("проспали") or msg.contains("прерван"):
			hud.fade_sleep()
		if msg != "":
			hud.show_toast(msg, 3.5))


func _on_effect_changed(id: StringName, added: bool) -> void:
	var def := Registry.get_entry("effects", id)
	var name: String = def.get("name", {}).get("ru", String(id))
	match String(def.get("kind", "")):
		"buff":
			if added:
				hud.show_toast(name)
		_:
			hud.show_toast(("Вы чувствуете: %s" if added else "Прошло: %s") % name, 3.0)


func _open_status() -> void:
	_status = StatusScreen.new()
	_status.survival = survival
	_status.player = player
	_status.closed.connect(func() -> void:
		_status = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	add_child(_status)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Смерть: вещи выпадают (если так на сложности), экран смерти. Хардкор — мир помечается.
func _on_died(cause: String) -> void:
	if _window != null:
		_window.close()
	if _status != null:
		_status.close()
	var diff := survival.difficulty_def()
	var note := ""
	if diff.get("drop_on_death", true):
		var b := player.body
		var rng := RandomNumberGenerator.new()
		for st in player.inventory.take_all():
			var a := rng.randf() * TAU
			dropped.spawn(st, b.x, b.y + 1.0, b.z, cos(a) * 2.0, 3.0, sin(a) * 2.0, 0.0)
		note = "Вещи остались на месте гибели"
	_death = DeathScreen.new()
	_death.cause = cause
	_death.registry = Registry
	_death.days = survival.clock.day
	_death.one_life = diff.get("one_life", false)
	_death.drop_note = note
	_death.respawn_requested.connect(_respawn)
	_death.menu_requested.connect(func() -> void:
		save_game()
		get_tree().change_scene_to_file(MENU_SCENE))
	add_child(_death)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _death.one_life and save != null:
		save.meta["hardcore_dead"] = true
		save_game()


func _respawn() -> void:
	_death = null
	var p := survival.respawn_point(_world_spawn)
	var x: float = p[0]
	var z: float = p[2]
	var y: float = p[1]
	if not survival.spawn.has("bed"):
		# Точка мира: поверхность по генератору (колонна может быть не загружена).
		y = float(maxi(world.generator.surface_height(floori(x), floori(z)), world.generator.sea_level) + 1)
	survival.respawn()
	player.teleport(x, y, z)
	player.motor.vx = 0.0
	player.motor.vy = 0.0
	player.motor.vz = 0.0
	player.active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_toast("Вы возродились %s" % ("у кровати" if survival.spawn.has("bed") else "в начале мира"))


func execute_inventory(a: InventoryAction) -> bool:
	return inv_ops.execute(a)


func open_inventory() -> void:
	_open_window(null, "")


## Ремесло: станции в мире, книга рецептов, тепло станций для выживания.
func _setup_crafting(pmeta: Dictionary) -> void:
	stations = StationSystem.new()
	stations.name = "Stations"
	add_child(stations)
	stations.setup(world, CraftingData.shared(Registry), survival.clock)
	crafting = CraftingController.new()
	crafting.name = "Crafting"
	add_child(crafting)
	crafting.setup(world, player, stations)
	crafting.from_dict(pmeta.get("recipes", {}))
	crafting.book.note_inventory(player.inventory)
	survival.probe.heat_sources = stations.heat_sources
	player.interaction.station_requested.connect(open_station)
	crafting.forge_requested.connect(_open_forge)
	stations.job_done.connect(func(p: Vector3i, _r: StringName) -> void:
		if p == _station_pos:
			Audio.play_ui("crafting/done"))


## Окно станции: панель станции над инвентарём игрока.
func open_station(pos: Vector3i) -> void:
	if _window != null:
		return
	var st := stations.station_at(pos)
	if st == null:
		return
	_station_pos = pos
	inv_ops.station = {}
	for pair: Array in [["st_in", st.inputs], ["st_fuel", st.fuel], ["st_out", st.outputs]]:
		if (pair[1] as Inventory).size() > 0:
			inv_ops.station[pair[0]] = pair[1]
	_open_window(null, "", st)
	Audio.play_at(String(st.def.get("sound", "stations/open")), world.to_scene(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5))


func _open_forge(pos: Vector3i, recipe_id: StringName, material: StringName) -> void:
	var st := stations.get_station(pos)
	var r := crafting.data.recipe(recipe_id)
	if st == null or r.is_empty():
		return
	var fw := ForgeWindow.new()
	var part: Dictionary = crafting.data.parts.get(StringName(r["output"]["id"]), {})
	fw.game = ForgeGame.new(part.get("forge_profile", []))
	fw.title = "%s (%s)" % [crafting.data.recipe_name(r), crafting.data.material_name(material).to_lower()]
	fw.can_heat = func() -> bool: return stations.heat_near(pos, 4, crafting.forge_heat(material))
	fw.slow = bool(Settings.get_value("slow_minigames"))
	fw.finished.connect(func(score: float) -> void:
		if crafting.finish_forge(st, r, material, score):
			hud.show_toast("Поковка: %s" % crafting.data.quality_name(crafting.data.quality_level(
				CraftingData.combine_score(CraftingData.RAW_SCORE, score, float(st.def.get("quality_bonus", 0.0)))))))
	add_child(fw)


func open_container(pos: Vector3i) -> void:
	var inv := world.get_container(pos.x, pos.y, pos.z)
	if inv == null or _window != null:
		return
	var def := Registry.block_by_num(world.get_block(pos.x, pos.y, pos.z))
	Audio.play_at("containers/%s_open" % def.container_kind, world.to_scene(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5))
	_open_window(inv, def.display_name())


func _open_window(container: Inventory, title: String, station: Station = null) -> void:
	inv_ops.container = container
	_window = InventoryWindow.new()
	_window.crafting = crafting
	_window.ops = inv_ops
	_window.player_inv = player.inventory
	_window.registry = Registry
	_window.executor = execute_inventory
	_window.creative = world.game_mode == &"creative" and container == null
	_window.container_title = title
	_window.appearance = player.appearance
	_window.closed.connect(_on_window_closed)
	if station != null:
		var panel := StationPanel.new()
		panel.controller = crafting
		panel.station = station
		panel.pos = _station_pos
		panel.window = _window
		_window.station_panel = panel
	add_child(_window)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_ui("ui/inventory_open")


func _on_window_closed() -> void:
	_window = null
	inv_ops.container = null
	if not inv_ops.station.is_empty():
		inv_ops.station = {}
		stations.flush(_station_pos)
		_station_pos = Vector3i(0, -10000, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_ui("ui/inventory_close")


## Выброшенное игроком летит вперёд по взгляду.
func _throw_from_player(stack: ItemStack) -> void:
	var eye := player.eye_world()
	var dir := player.look_dir()
	dropped.spawn(stack, eye[0] + dir.x * 0.4, eye[1] - 0.3, eye[2] + dir.z * 0.4, dir.x * 5.0, dir.y * 5.0 + 2.0,
		dir.z * 5.0, 1.2)


func _on_loaded() -> void:
	_loading = false
	_screenshot_wait = 0.0
	hud.set_loading(false)
	# В режиме скриншота игрок заморожен — кадр повторяем.
	player.active = GameLaunch.screenshot_path == ""
	survival.running = true
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


## Скриншот станций: ставит станции перед игроком, наполняет и открывает окно.
func _screenshot_station(kind: String) -> void:
	var b := player.body
	var base := Vector3i(floori(b.x), floori(b.y), floori(b.z) - 3)
	var ground := func(x: int, z: int) -> int:
		var y := base.y + 3
		while y > base.y - 6 and not world.is_solid(x, y - 1, z):
			y -= 1
		return y
	var place := func(id: StringName, dx: int, facing: int = 2) -> Vector3i:
		var x := base.x + dx
		var y: int = ground.call(x, base.z)
		world.execute(GameAction.place_block(Vector3i(x, y, base.z), Registry.block_num(id), facing))
		return Vector3i(x, y, base.z)
	if kind == "station_row":
		var ids: Array[StringName] = [&"workbench", &"stone_furnace", &"bloomery", &"iron_anvil", &"grindstone",
			&"spinning_wheel", &"loom", &"campfire"]
		for i in ids.size():
			var p: Vector3i = place.call(ids[i], i * 2 - 7)
			var st := stations.station_at(p)
			if st != null and st.fuel.size() > 0:
				st.fuel.set_stack(0, ItemStack.make(&"charcoal", 8))
				st.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 4))
				st.advance(8.0)
		stations.viewer = Vector3(b.x, b.y, b.z)
		stations._process(1.0)
		return
	if kind == "workbench":
		var p: Vector3i = place.call(&"workbench", 0)
		var st := stations.station_at(p)
		st.inputs.set_stack(0, ItemStack.make(&"pickaxe_head", 1, { "material": "bronze", "quality": 2, "quenched": true }))
		st.inputs.set_stack(1, ItemStack.make(&"haft", 1, { "material": "oak", "quality": 1 }))
		st.inputs.set_stack(2, ItemStack.make(&"binding", 1, { "material": "leather", "quality": 1 }))
		for id: StringName in [&"oak_planks", &"stick", &"rope", &"granite", &"clay"]:
			player.inventory.add(ItemStack.create(Registry.item(id), 16))
		crafting.book.note_inventory(player.inventory)
		open_station(p)
		return
	if kind == "furnace" or kind == "forge":
		var p: Vector3i = place.call(&"bloomery", 0)
		var st := stations.station_at(p)
		st.auto = kind == "forge"
		st.fuel.set_stack(0, ItemStack.make(&"charcoal", 12))
		st.inputs.set_stack(0, ItemStack.make(&"copper_ingot", 7))
		st.inputs.set_stack(1, ItemStack.make(&"tin_ingot", 1))
		crafting.book.note_items([&"copper_ingot", &"tin_ingot"])
		for i in 20:
			st.pump()
			st.advance(0.5)
		if kind == "furnace":
			open_station(p)
			return
		var a: Vector3i = place.call(&"bronze_anvil", 2)
		player.inventory.add(ItemStack.make(&"bronze_ingot", 6, { "quality": 2 }))
		var anvil := stations.station_at(a)
		crafting.minigames = true
		crafting.start_recipe(anvil, a, crafting.data.recipe(&"forge_pickaxe_head"), 1, &"bronze")
		return
	if kind == "campfire":
		var p: Vector3i = place.call(&"campfire", 0)
		var st := stations.station_at(p)
		st.auto = false
		st.fuel.set_stack(0, ItemStack.make(&"oak_log", 4))
		st.inputs.set_stack(0, ItemStack.make(&"raw_meat", 3))
		st.advance(6.2)
		open_station(p)


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
	if GameLaunch.open_ui == "inventory":
		open_inventory()
	elif GameLaunch.open_ui in ["furnace", "workbench", "forge", "campfire", "station_row"]:
		_screenshot_station(GameLaunch.open_ui)
	elif GameLaunch.open_ui in ["craft", "book"]:
		InventoryWindow._remembered_tab = 1 if GameLaunch.open_ui == "craft" else 2
		for id: StringName in [&"birch_log", &"stick", &"twine", &"flint"]:
			player.inventory.add(ItemStack.create(Registry.item(id), 4))
		crafting.book.note_items([&"iron_concentrate", &"copper_concentrate", &"tin_concentrate", &"raw_meat"])
		open_inventory()
	elif GameLaunch.open_ui == "status":
		survival.vitals.hunger = 46.0
		survival.vitals.thirst = 18.0
		survival.vitals.health = 72.0
		survival.vitals.add_effect(&"cold")
		survival.vitals.add_effect(&"well_fed")
		survival.vitals.add_effect(&"splinted")
		_open_status()
	elif GameLaunch.open_ui == "chest":
		var b := player.body
		var p := Vector3i(floori(b.x) + 2, floori(b.y), floori(b.z))
		world.set_block(p.x, p.y, p.z, Registry.block_num(&"chest_wood"))
		var inv := world.get_container(p.x, p.y, p.z)
		for id: StringName in [&"granite", &"stick", &"bilberries", &"iron_pickaxe", &"fur_coat", &"torch"]:
			inv.add(ItemStack.create(Registry.item(id), 20))
		open_container(p)
	# Поставленные блоки (станции) — дождаться света и меша.
	for i in 120:
		if ch.pending_meshing() == 0 and ch.pending_lighting() == 0:
			break
		await get_tree().process_frame
	for i in 8:
		await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(GameLaunch.screenshot_path)
	print("Скриншот: %s (%s), колонн %d, граней %d" % [GameLaunch.screenshot_path, error_string(err), ch.columns.size(), ch.stat_quads])
	world.chunks.wait_all()
	get_tree().quit(0 if err == OK else 1)
