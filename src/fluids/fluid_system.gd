class_name FluidSystem
extends Node
## Жидкости в игре (этап 8): шаги FluidSim с периодом tick из data/fluids.json в радиусе
## sim_radius колонн вокруг игрока, пробуждение по правкам блоков и загрузке колонн, пар и
## шипение при застывании лавы, течение в точке (current_at) для игрока, предметов и лодки:
## в конечной воде — по перепаду уровней, в реке — вдоль русла из генератора.
## Шаг идёт в главном потоке с ограничением MAX_CELLS клеток: правки блоков должны применяться
## сразу (FluidSim пишет в мир), а изменения дальше мешатся и освещаются в пуле потоков.

## Радиус симуляции в колоннах (дальше вода «спит» до приближения игрока).
const SIM_RADIUS := 6
## Кэш течения рек: клетка 2×2 блока → Vector2 (чистая функция генератора, считается дорого).
const RIVER_CACHE_MAX := 4096

var world: World
var sim: FluidSim
var player: Player
var rig: GraphicsRig
## Камера под водой (для звука и HUD).
var underwater := false
var water := 0
var _tick := 0.2
var _left := 0.0
var _stepping := false
var _river_cache := {}
var _river_flow_speed := 1.0
var _water_flow_speed := 1.6
var _ripples: Array[Vector4] = []   # x, z (мировые), возраст, сила
var _ripple_left := 0.0
var _was_in_water := false
var _overlay: CanvasLayer
var _overlay_mat: ShaderMaterial
var _splash_mesh: QuadMesh
var _splash_process: ParticleProcessMaterial
var _steam_mesh: QuadMesh
var _steam_process: ParticleProcessMaterial
## Время последнего шага, мс (F3).
var stat_ms := 0.0


func _init() -> void:
	name = "Fluids"


func setup(p_world: World) -> void:
	world = p_world
	sim = FluidSim.new(world, world.registry)
	sim.radius = SIM_RADIUS
	water = world.registry.fluid_ids.find(&"water") + 1
	if water > 0:
		var e := world.registry.get_entry("fluids", &"water")
		_tick = float(e.get("tick", 0.2))
		_water_flow_speed = float(e.get("flow_speed", 1.6))
	world.block_changed.connect(_on_block_changed)
	world.chunks.column_loaded.connect(_on_column_loaded)
	_make_steam()
	_overlay = CanvasLayer.new()
	_overlay.layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = load("res://src/fluids/underwater.gdshader")
	rect.material = _overlay_mat
	_overlay.add_child(rect)
	_overlay.visible = false
	add_child(_overlay)


func _process(delta: float) -> void:
	_update_view(delta)
	_left -= delta
	if _left > 0.0:
		return
	_left = _tick
	if sim.active_count() == 0:
		stat_ms = 0.0
		return
	var t0 := Time.get_ticks_usec()
	_stepping = true
	sim.step()
	_stepping = false
	stat_ms = (Time.get_ticks_usec() - t0) / 1000.0
	for p: Vector3i in sim.reactions:
		var at := world.to_scene(p.x + 0.5, p.y + 1.0, p.z + 0.5)
		_steam_at(at)
		Audio.play_at("fluids/lava_hiss", at)


## Центр симуляции — колонна игрока (просыпаются спящие колонны рядом).
func set_center(x: float, z: float) -> void:
	sim.set_center(Vector2i(floori(x) >> 4, floori(z) >> 4))


## Течение в мировой точке, блоков/с (мировые оси): игрок, предметы, лодка.
func current_at(x: float, y: float, z: float) -> Vector3:
	var p := Vector3i(floori(x), floori(y), floori(z))
	var b := world.get_block(p.x, p.y, p.z)
	if b <= 0 or world.registry.block_fluid[b] == 0:
		return Vector3.ZERO
	if world.registry.block_fluid_source[b] == 1:
		if world.registry.block_fluid[b] != water:
			return Vector3.ZERO
		var key := Vector2i(p.x >> 1, p.z >> 1)
		var f: Variant = _river_cache.get(key)
		if f == null:
			if _river_cache.size() > RIVER_CACHE_MAX:
				_river_cache.clear()
			f = world.generator.river_flow(float(key.x * 2 + 1), float(key.y * 2 + 1))
			_river_cache[key] = f
		var v: Vector2 = f
		return Vector3(v.x, 0.0, v.y)
	return sim.flow_at(p) * _water_flow_speed


## Под водой ли камера, круги от шагов и след плывущего, всплеск при входе в воду.
func _update_view(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and rig != null:
		var cp := cam.global_position + Vector3(world.origin)
		var level := liquid_surface(cp.x, cp.y, cp.z)
		var under := level > cp.y and _is_water(floori(cp.x), floori(cp.y), floori(cp.z))
		if under != underwater:
			underwater = under
			_overlay.visible = under
			Audio.set_underwater(under)
		if under:
			var c := water_color(floori(cp.x), floori(cp.z))
			rig.set_underwater(true, c)
			_overlay_mat.set_shader_parameter(&"tint", c.lightened(0.2))
		else:
			rig.set_underwater(false)
	if player != null:
		var b := player.body
		var feet := _is_water(floori(b.x), floori(b.y + 0.1), floori(b.z))
		var surface := liquid_surface(b.x, b.y + 0.1, b.z)
		var at_surface := feet and absf(surface - (b.y + 0.9)) < 1.0
		var moving := Vector2(player.motor.vx, player.motor.vz).length()
		_ripple_left -= delta
		if at_surface and moving > 0.6 and _ripple_left <= 0.0:
			_ripple_left = 0.35 if player.motor.in_fluid else 0.5
			add_ripple(b.x, b.z, 0.6 if player.motor.in_fluid else 0.35)
		if feet and not _was_in_water and player.motor.vy < -4.0:
			add_ripple(b.x, b.z, 1.4)
			var at := world.to_scene(b.x, surface, b.z)
			_splash_at(at, clampf(-player.motor.vy / 12.0, 0.3, 1.0))
			Audio.play_at("fluids/splash", at)
		_was_in_water = feet
	for i in range(_ripples.size() - 1, -1, -1):
		var r := _ripples[i]
		r.z += delta
		_ripples[i] = r
		if r.z > 3.0:
			_ripples.remove_at(i)
	var m := Projection()
	for i in 4:
		var r := _ripples[i] if i < _ripples.size() else Vector4.ZERO
		# Сдвиг на origin не нужен: шейдер берёт мировые координаты (world_origin + сценовые).
		m[i] = r
	RenderingServer.global_shader_parameter_set(&"ripples", m)


## Круг на воде в мировой точке (не больше 4 одновременно — старые вытесняются).
func add_ripple(x: float, z: float, strength: float) -> void:
	_ripples.push_front(Vector4(x, z, 0.0, strength))
	if _ripples.size() > 4:
		_ripples.resize(4)


## Высота поверхности жидкости над точкой (World.liquid_surface).
func liquid_surface(x: float, y: float, z: float) -> float:
	return world.liquid_surface(x, y, z)


func _is_water(x: int, y: int, z: int) -> bool:
	var b := world.get_block(x, y, z)
	return b > 0 and world.registry.block_fluid[b] == water and water > 0


## Цвет воды биома в мировой точке.
func water_color(x: int, z: int) -> Color:
	var bi := world.biome_at(x, z)
	var bs := world.generator.biomes
	return bs.water_colors[bi] if bi >= 0 and bi < bs.water_colors.size() else Color(0.18, 0.37, 0.52)


func _splash_at(at: Vector3, power: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = roundi(10 + 30 * power)
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.process_material = _splash_process
	p.draw_pass_1 = _splash_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.2, false).timeout.connect(p.queue_free)


func _on_block_changed(p: Vector3i, _old: int, _new: int) -> void:
	if not _stepping:
		sim.wake(p)


func _on_column_loaded(c: Vector2i) -> void:
	sim.wake_column(c, world.chunks.columns.get(c))


## Облачко пара (лава + вода): одноразовый эмиттер, исчезает сам.
func _steam_at(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.5
	p.local_coords = false
	p.process_material = _steam_process
	p.draw_pass_1 = _steam_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.0, false).timeout.connect(p.queue_free)


func _make_steam() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.6, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_steam_process = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var tex := "res://assets/textures/generated/particles/smoke.png"
	if ResourceLoader.exists(tex):
		mat.albedo_texture = load(tex)
	var sp := ParticleProcessMaterial.new()
	sp.direction = Vector3.UP
	sp.spread = 35.0
	sp.initial_velocity_min = 2.5
	sp.initial_velocity_max = 5.0
	sp.gravity = Vector3(0, -12.0, 0)
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	sp.emission_ring_axis = Vector3.UP
	sp.emission_ring_radius = 0.5
	sp.emission_ring_inner_radius = 0.2
	sp.emission_ring_height = 0.05
	sp.scale_min = 0.5
	sp.scale_max = 1.2
	_splash_process = sp
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.albedo_color = Color(0.85, 0.9, 1.0, 0.8)
	var stex := "res://assets/textures/generated/particles/splash.png"
	if ResourceLoader.exists(stex):
		smat.albedo_texture = load(stex)
	_splash_mesh = QuadMesh.new()
	_splash_mesh.size = Vector2(0.25, 0.25)
	_splash_mesh.material = smat
	_steam_mesh = QuadMesh.new()
	_steam_mesh.size = Vector2(0.8, 0.8)
	_steam_mesh.material = mat
