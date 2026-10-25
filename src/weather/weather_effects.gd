class_name WeatherEffects
extends Node3D
## Видимая погода (раздел 3.3 ТЗ): GPU-частицы вокруг камеры — дождь (тысячи капель, штрих по
## скорости, коллизия по карте высот: под крышей дождя нет; брызги при ударе — субэмиттер),
## снег (кружит турбулентностью), град (отскакивает), пыль суховея, осенний листопад, капли с
## краёв крыш (точки находит CPU раз в DRIP_INTERVAL); молния — ветвящийся процедурный меш со
## вспышкой света. Плотность — настройка «Частицы». Всё в сценовых координатах (floating origin:
## частицы короткоживущие, точки капель пересчитываются).

const TEX := "res://assets/textures/generated/particles/"
## Полуразмер области осадков вокруг камеры, блоки.
const AREA := 34.0
const DROP_HEIGHT := 18.0
const DRIP_INTERVAL := 1.5
const DRIP_POINTS := 32
## Число частиц при «высоком» качестве.
const RAIN_MAX := 9000
const SNOW_MAX := 6000
const HAIL_MAX := 1600
const SPLASH_MAX := 1500
const DUST_MAX := 160
const LEAF_MAX := 140
const DRIP_MAX := 240
const BOLT_LIFE := 0.5

var world: World
## Доля частиц 0…1 (настройка «Частицы»).
var density := 1.0
var reduce_flashing := false
var rain: GPUParticles3D
var splash: GPUParticles3D
var snow: GPUParticles3D
var hail: GPUParticles3D
var dust: GPUParticles3D
var leaves: GPUParticles3D
var drips: GPUParticles3D
var heightfield: GPUParticlesCollisionHeightField3D
var _rain_mat: ShaderMaterial
var _drip_mat: ShaderMaterial
var _flake_mat: StandardMaterial3D
var _hail_mat: StandardMaterial3D
var _bolts: Array = []   # [MeshInstance3D, OmniLight3D, жизнь]
var _drip_left := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "WeatherEffects"
	_rng.randomize()


func setup(p_world: World) -> void:
	world = p_world
	heightfield = GPUParticlesCollisionHeightField3D.new()
	heightfield.size = Vector3(AREA * 2.4, 140.0, AREA * 2.4)
	heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	heightfield.follow_camera_enabled = true
	heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(heightfield)

	splash = _particles(SPLASH_MAX, 0.35, _billboard("splash", 0.22, Color(0.85, 0.9, 1.0, 0.7)))
	var sp := _proc_mat(Vector3.ZERO, 1.0, 2.2, 0.0)
	sp.direction = Vector3.UP
	sp.spread = 55.0
	sp.gravity = Vector3(0, -9.0, 0)
	sp.scale_min = 0.5
	sp.scale_max = 1.0
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	splash.process_material = sp

	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = load("res://src/weather/rain_streak.gdshader")
	_rain_mat.set_shader_parameter(&"streak_tex", _tex("rain"))
	rain = _particles(RAIN_MAX, 2.2, _mesh(_rain_mat))
	var rp := _proc_mat(Vector3(AREA * 0.7, DROP_HEIGHT * 0.5, AREA * 0.7), 15.0, 19.0, 6.0)
	rp.particle_flag_align_y = true
	rp.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	rp.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	rp.sub_emitter_amount_at_collision = 1
	rain.process_material = rp
	rain.collision_base_size = 0.05

	var flake := _billboard("snowflake", 0.12, Color(1, 1, 1, 0.95))
	_flake_mat = flake.material
	snow = _particles(SNOW_MAX, 10.0, flake)
	var snp := _proc_mat(Vector3(AREA * 0.6, DROP_HEIGHT * 0.6, AREA * 0.6), 1.2, 2.2, 0.35)
	snp.turbulence_enabled = true
	snp.turbulence_noise_strength = 1.6
	snp.turbulence_noise_scale = 5.0
	snp.turbulence_influence_min = 0.05
	snp.turbulence_influence_max = 0.15
	snp.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	snp.scale_min = 0.6
	snp.scale_max = 1.3
	snow.process_material = snp

	var stone := _billboard("hail", 0.07, Color(0.92, 0.95, 1.0, 1.0))
	_hail_mat = stone.material
	hail = _particles(HAIL_MAX, 2.6, stone)
	var hp := _proc_mat(Vector3(AREA * 0.7, DROP_HEIGHT * 0.5, AREA * 0.7), 18.0, 22.0, 9.0)
	hp.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	hp.collision_bounce = 0.35
	hp.collision_friction = 0.5
	hp.scale_min = 0.6
	hp.scale_max = 1.4
	hail.process_material = hp

	dust = _particles(DUST_MAX, 6.0, _billboard("dust", 3.2, Color(0.8, 0.7, 0.52, 0.22)))
	var dp := _proc_mat(Vector3(AREA, 5.0, AREA), 7.0, 11.0, 0.0)
	dp.direction = Vector3(1, 0, 0)
	dp.spread = 12.0
	dp.angle_min = 0.0
	dp.angle_max = 360.0
	dp.scale_min = 0.6
	dp.scale_max = 1.6
	dust.process_material = dp

	var leaf := _billboard("leaf", 0.22, Color(1, 1, 1, 1))
	(leaf.material as StandardMaterial3D).vertex_color_use_as_albedo = true
	leaves = _particles(LEAF_MAX, 8.0, leaf)
	var lp := _proc_mat(Vector3(AREA * 0.6, 4.0, AREA * 0.6), 0.3, 1.0, 0.6)
	lp.turbulence_enabled = true
	lp.turbulence_noise_strength = 2.5
	lp.turbulence_noise_scale = 3.0
	lp.turbulence_influence_min = 0.1
	lp.turbulence_influence_max = 0.25
	lp.angle_min = 0.0
	lp.angle_max = 360.0
	lp.angular_velocity_min = -160.0
	lp.angular_velocity_max = 160.0
	lp.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	lp.collision_friction = 1.0
	lp.collision_bounce = 0.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([Color(0.93, 0.74, 0.2), Color(0.9, 0.45, 0.12), Color(0.72, 0.2, 0.1), Color(0.5, 0.33, 0.18)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	lp.color_initial_ramp = gt
	leaves.process_material = lp

	_drip_mat = ShaderMaterial.new()
	_drip_mat.shader = _rain_mat.shader
	_drip_mat.set_shader_parameter(&"streak_tex", _tex("rain"))
	_drip_mat.set_shader_parameter(&"size", Vector2(0.03, 0.16))
	drips = _particles(DRIP_MAX, 1.0, _mesh(_drip_mat))
	var drp := ParticleProcessMaterial.new()
	drp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	drp.gravity = Vector3(0, -14.0, 0)
	drp.particle_flag_align_y = true
	drp.initial_velocity_min = 0.0
	drp.initial_velocity_max = 0.3
	drp.direction = Vector3.DOWN
	drp.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	drips.process_material = drp
	drips.emitting = false

	for p: GPUParticles3D in [splash, rain, snow, hail, dust, leaves, drips]:
		add_child(p)
	rain.sub_emitter = rain.get_path_to(splash)
	set_density(density)


## Доля частиц 0…1 (смена количества перезапускает эмиттеры).
func set_density(d: float) -> void:
	density = clampf(d, 0.1, 1.0)
	if rain == null:
		return
	for pair: Array in [[rain, RAIN_MAX], [snow, SNOW_MAX], [hail, HAIL_MAX], [splash, SPLASH_MAX], [dust, DUST_MAX],
			[leaves, LEAF_MAX], [drips, DRIP_MAX]]:
		(pair[0] as GPUParticles3D).amount = maxi(8, roundi(float(pair[1]) * density))


## Каждый кадр: cam — сценовая позиция камеры, w — WeatherSim.values, leaf — доля листвы вокруг
## (0…1) для листопада, autumn — идёт ли осень.
func update(delta: float, cam: Vector3, w: Dictionary, daylight: float, leaf: float, autumn: bool) -> void:
	var wd: Vector2 = w.get("wind_dir", Vector2(1, 0))
	var wind := float(w.get("wind", 0.0))
	# Центр области осадков: капли рождаются по всей высоте 0…2·DROP_HEIGHT над камерой, так что
	# после включения дождь сразу вокруг, а не через секунду падения.
	var top := cam + Vector3(0.0, DROP_HEIGHT * 0.6, 0.0)
	var r := float(w.get("rain", 0.0))
	var s := float(w.get("snow", 0.0))
	var h := float(w.get("hail", 0.0))
	var d := float(w.get("dust", 0.0))
	var bright := 0.12 + 0.88 * daylight
	rain.global_position = top
	snow.global_position = top
	hail.global_position = top
	dust.global_position = cam + Vector3(0.0, 2.0, 0.0)
	leaves.global_position = cam + Vector3(0.0, 9.0, 0.0)
	var slant := Vector3(wd.x, 0.0, wd.y) * wind
	(rain.process_material as ParticleProcessMaterial).direction = (Vector3.DOWN + slant * 0.35).normalized()
	(hail.process_material as ParticleProcessMaterial).direction = (Vector3.DOWN + slant * 0.25).normalized()
	(snow.process_material as ParticleProcessMaterial).direction = (Vector3.DOWN + slant * 1.4).normalized()
	(dust.process_material as ParticleProcessMaterial).direction = Vector3(wd.x, 0.05, wd.y)
	(leaves.process_material as ParticleProcessMaterial).direction = (Vector3.DOWN + slant * 1.5).normalized()
	_rain_mat.set_shader_parameter(&"brightness", bright)
	_drip_mat.set_shader_parameter(&"brightness", bright)
	_flake_mat.albedo_color = Color(bright, bright, bright, 0.95)
	_hail_mat.albedo_color = Color(0.92 * bright, 0.95 * bright, bright, 1.0)
	_level(rain, r)
	_level(snow, s)
	_level(hail, h)
	_level(dust, d)
	_level(leaves, leaf * (0.35 + 0.65 * wind) if autumn else 0.0)
	_drip_left -= delta
	if _drip_left <= 0.0:
		_drip_left = DRIP_INTERVAL
		_update_drips(cam, r)
	_update_bolts(delta)


func _level(p: GPUParticles3D, k: float) -> void:
	var on := k > 0.01
	if p.emitting != on:
		p.emitting = on
	if on:
		p.amount_ratio = clampf(k, 0.05, 1.0)


## Капли с краёв крыш: нижняя кромка блока, над которым открытое небо, под ним — воздух,
## а рядом сбоку — открытая колонна (вода стекает с края).
func _update_drips(cam: Vector3, r: float) -> void:
	if r < 0.15 or world == null:
		drips.emitting = false
		return
	var o := cam + Vector3(world.origin)
	var pts := PackedVector3Array()
	for i in 160:
		if pts.size() >= DRIP_POINTS:
			break
		var x := floori(o.x) + _rng.randi_range(-14, 14)
		var z := floori(o.z) + _rng.randi_range(-14, 14)
		var y := LightningTarget.top_y(world, x, z)
		if y < WorldConst.MIN_Y or world.get_block(x, y - 1, z) != 0 or not world.is_solid(x, y, z):
			continue
		for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if LightningTarget.top_y(world, x + dv.x, z + dv.y) < y - 1:
				var p := world.to_scene(x + 0.5 + dv.x * 0.45, float(y) - 0.02, z + 0.5 + dv.y * 0.45)
				pts.append(p)
				break
	if pts.is_empty():
		drips.emitting = false
		return
	var img := Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
	for i in pts.size():
		img.set_pixel(i, 0, Color(pts[i].x, pts[i].y, pts[i].z))
	var pm := drips.process_material as ParticleProcessMaterial
	pm.emission_point_texture = ImageTexture.create_from_image(img)
	pm.emission_point_count = pts.size()
	drips.amount_ratio = clampf(r, 0.2, 1.0)
	drips.emitting = true


## Удар молнии в сценовую точку at: ветвящийся канал от облаков, вспышка света.
func strike(at: Vector3, cam: Vector3, strength: float = 1.0) -> void:
	var top := at + Vector3(_rng.randf_range(-30.0, 30.0), 150.0, _rng.randf_range(-30.0, 30.0))
	var main := bolt_points(top, at, _rng, 7, 0.22)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(im, main, cam, 0.45)
	for b in _rng.randi_range(3, 6):
		var i := _rng.randi_range(4, main.size() / 2 + 4) % main.size()
		var start := main[i]
		var len := _rng.randf_range(15.0, 45.0)
		var end := start + Vector3(_rng.randf_range(-1.0, 1.0), -_rng.randf_range(0.6, 1.2), _rng.randf_range(-1.0, 1.0)).normalized() * len
		_ribbon(im, bolt_points(start, end, _rng, 5, 0.28), cam, 0.18)
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(2.6, 2.7, 3.4) * (0.4 if reduce_flashing else 1.0)
	mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.omni_range = 90.0
	light.light_color = Color(0.8, 0.85, 1.0)
	light.light_energy = (2.0 if reduce_flashing else 7.0) * strength
	add_child(light)
	light.global_position = at + Vector3(0, 12, 0)
	_bolts.append([mi, light, BOLT_LIFE])


func _update_bolts(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Array = _bolts[i]
		b[2] = float(b[2]) - delta
		var life: float = b[2]
		var mi: MeshInstance3D = b[0]
		var light: OmniLight3D = b[1]
		if life <= 0.0:
			mi.queue_free()
			light.queue_free()
			_bolts.remove_at(i)
			continue
		# Мерцание: канал гаснет и вспыхивает повторно (без мерцания при «меньше вспышек»).
		var t := BOLT_LIFE - life
		var on := reduce_flashing or t < 0.08 or (t > 0.16 and t < 0.24) or (t > 0.3 and t < 0.34)
		mi.visible = on
		light.visible = on
		light.light_energy *= 0.9


## Точки ветвящегося канала: смещение середины отрезков (detail уровней), jitter — доля длины.
static func bolt_points(a: Vector3, b: Vector3, rng: RandomNumberGenerator, detail: int, jitter: float) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var amp := a.distance_to(b) * jitter
	for level in detail:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			var p := pts[i]
			var q := pts[i + 1]
			next.append(p)
			var m := (p + q) * 0.5 + Vector3(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp) * 0.3, rng.randf_range(-amp, amp))
			next.append(m)
		next.append(pts[pts.size() - 1])
		pts = next
		amp *= 0.5
	return pts


## Лента из отрезков, повёрнутая к камере (сужается к концу).
func _ribbon(im: ImmediateMesh, pts: PackedVector3Array, cam: Vector3, width: float) -> void:
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var w0 := width * (1.0 - float(i) / pts.size() * 0.6)
		var w1 := width * (1.0 - float(i + 1) / pts.size() * 0.6)
		var side := (q - p).cross(cam - p).normalized()
		im.surface_add_vertex(p - side * w0)
		im.surface_add_vertex(p + side * w0)
		im.surface_add_vertex(q + side * w1)
		im.surface_add_vertex(p - side * w0)
		im.surface_add_vertex(q + side * w1)
		im.surface_add_vertex(q - side * w1)


func _particles(amount: int, lifetime: float, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.draw_pass_1 = mesh
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-AREA - 10.0, -80.0, -AREA - 10.0), Vector3(AREA * 2.0 + 20.0, 110.0, AREA * 2.0 + 20.0))
	p.fixed_fps = 0
	return p


func _proc_mat(box: Vector3, vmin: float, vmax: float, gravity: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.DOWN
	pm.spread = 3.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0.0, -gravity, 0.0)
	return pm


## Квад-билборд с текстурой частицы (материал — mesh.material).
func _billboard(tex: String, size: float, color: Color) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = _tex(tex)
	m.albedo_color = color
	m.disable_receive_shadows = true
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


func _mesh(mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.material = mat
	return q


func _tex(n: String) -> Texture2D:
	var path := TEX + n + ".png"
	return load(path) if ResourceLoader.exists(path) else null
