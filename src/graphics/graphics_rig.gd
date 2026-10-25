class_name GraphicsRig
extends Node3D
## Окружение и настройки графики (этап 3, раздел 16 ТЗ): атмосферное небо с рассеянием,
## солнце с каскадными тенями, SSAO/SSIL, объёмный и дальний туман, glow, тонмаппинг AgX,
## автоэкспозиция (выход из пещеры ослепляет), цветокоррекция по климату биома.
## Значения качества — из Settings.graphics (data/graphics_presets.json).
##
## Сутки и погода (этап 7): своё небо (src/graphics/sky.gdshader) — солнце по дуге окна дня
## сезона, луна с фазами, звёзды и Млечный Путь, 2.5D-облака по ветру с тенями на блоках
## (глобальный параметр cloud_shadow), пасмурность, дымка, вспышки молний, цветокоррекция
## по погоде. Глобальные параметры шейдеров: wind, cloud_shadow, rain_wetness.

## Скорость смены цветокоррекции при переходе между биомами (доля за секунду).
const GRADE_SPEED := 0.6
## Облака: высота плоскости над камерой и размер плитки текстуры (блоки).
const CLOUD_HEIGHT := 180.0
const CLOUD_TILE := 1024.0
## Насколько тень облака гасит прямой свет на блоках.
const CLOUD_SHADOW := 0.45
## Высота полюса мира (вокруг него вращаются звёзды), градусы.
const POLE_ELEV := 52.0
const MOON_TEX := "res://assets/textures/generated/sky/moon.png"
const STARS_TEX := "res://assets/textures/generated/sky/night_sky.png"
const CLOUDS_TEX := "res://assets/textures/generated/sky/clouds.png"

var environment: Environment
var sun: DirectionalLight3D
## Лунный свет: тусклый холодный, сила — по освещённой доле диска и высоте луны.
var moon: DirectionalLight3D
var camera_attributes: CameraAttributesPractical
var sky_shader: ShaderMaterial
## Сила лунного света в полнолуние (data/sky.json → moon_light).
var moon_light := 0.2
var world_environment: WorldEnvironment
var graphics := {}

var _grade_target := Vector4(1.0, 1.0, 1.0, 0.0)   # насыщенность, контраст, яркость, теплота
var _grade := Vector4(1.0, 1.0, 1.0, 0.0)
## Дневной свет 0 (ночь) … 1 (день) — для неба, солнца и рассеянного света.
var daylight := 1.0
var _sun_color := Color(1.0, 0.97, 0.92)
var _weather_grade := Vector4.ZERO
var _moon_illum := 1.0
var _moon_up := 0.0
var _cover := 0.3
var _darkness := 0.0
var _fog := 0.0
var _dust := 0.0
var _rain := 0.0
var _snow := 0.0
var _flash := 0.0
var _wind := Vector4(0.8, 0.6, 0.5, 0.0)
var _cloud_shift := Vector2.ZERO
var _sun_shift := Vector2.ZERO
var _cloud_quality := 2
var _fog_near := 120.0
var _fog_far := 200.0


func _init() -> void:
	name = "GraphicsRig"
	sky_shader = ShaderMaterial.new()
	sky_shader.shader = load("res://src/graphics/sky.gdshader")
	for pair: Array in [[&"moon_tex", MOON_TEX], [&"stars_tex", STARS_TEX], [&"clouds_tex", CLOUDS_TEX]]:
		if ResourceLoader.exists(pair[1]):
			sky_shader.set_shader_parameter(pair[0], load(pair[1]))
	sky_shader.set_shader_parameter(&"cloud_height", CLOUD_HEIGHT)
	sky_shader.set_shader_parameter(&"cloud_tile", CLOUD_TILE)
	var sky := Sky.new()
	sky.sky_material = sky_shader
	# Солнце и облака движутся постоянно: кубическая карта отражений обновляется по частям.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_white = 6.0
	# Дальний туман сливает край прорисовки с небом (aerial perspective берёт цвет неба).
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = Color(0.62, 0.72, 0.86)
	environment.fog_aerial_perspective = 0.85
	environment.fog_sun_scatter = 0.15
	environment.fog_sky_affect = 0.0
	environment.fog_depth_curve = 1.6
	# Объёмный туман: лучи солнца сквозь кроны, мягкая дымка.
	environment.volumetric_fog_density = 0.006
	environment.volumetric_fog_albedo = Color(0.9, 0.93, 1.0)
	environment.volumetric_fog_anisotropy = 0.55
	environment.volumetric_fog_length = 96.0
	environment.volumetric_fog_ambient_inject = 0.0
	environment.volumetric_fog_sky_affect = 0.0
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.6
	environment.ssao_light_affect = 0.15
	environment.ssil_radius = 6.0
	environment.ssil_intensity = 0.8
	environment.adjustment_enabled = true

	camera_attributes = CameraAttributesPractical.new()
	camera_attributes.auto_exposure_scale = 0.45
	camera_attributes.auto_exposure_speed = 0.6
	camera_attributes.auto_exposure_min_sensitivity = 60.0
	camera_attributes.auto_exposure_max_sensitivity = 900.0

	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	world_environment.camera_attributes = camera_attributes
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_blend_splits = true
	sun.light_volumetric_fog_energy = 1.2
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.visible = false
	add_child(moon)
	set_time_of_day(13.0)
	set_weather({})


## Положение солнца по часу суток с постоянным окном 6:00–21:00 (фон меню, без сезона).
func set_time_of_day(hour: float) -> void:
	set_sky_time(hour, Vector2(6.0, 21.0), 0.5)


## Солнце, луна и звёзды (этап 7): дуга солнца по окну дня сезона (SkyMath), луна с фазой,
## небо вращается вокруг полюса мира (север, высота POLE_ELEV).
func set_sky_time(hour: float, window: Vector2, phase: float) -> void:
	var s := SkyMath.sun(hour, window)
	var m := SkyMath.moon(hour, window, phase)
	var sd := SkyMath.direction(s)
	var md := SkyMath.direction(m)
	_aim(sun, sd)
	_aim(moon, md)
	daylight = smoothstep(-6.0, 8.0, s.x)
	var low := 1.0 - smoothstep(4.0, 22.0, s.x)   # закатный тёплый свет
	_sun_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.62, 0.36), low * daylight)
	_moon_illum = SkyMath.moon_illumination(phase)
	_moon_up = smoothstep(-2.0, 6.0, m.x)
	sky_shader.set_shader_parameter(&"sun_dir", sd)
	sky_shader.set_shader_parameter(&"moon_dir", md)
	sky_shader.set_shader_parameter(&"moon_phase", phase)
	sky_shader.set_shader_parameter(&"daylight", daylight)
	sky_shader.set_shader_parameter(&"sun_color", Vector3(_sun_color.r, _sun_color.g, _sun_color.b))
	var pole := Vector3(0.0, sin(deg_to_rad(POLE_ELEV)), -cos(deg_to_rad(POLE_ELEV)))
	sky_shader.set_shader_parameter(&"star_rotation", Basis(pole, hour / 24.0 * TAU))
	_sun_shift = Vector2(sd.x, sd.z) / maxf(sd.y, 0.2) * CLOUD_HEIGHT
	_update_lights()


## DirectionalLight3D светит вдоль −Z: направляем его от светила к земле.
func _aim(light: DirectionalLight3D, to_light: Vector3) -> void:
	var up := Vector3.UP if absf(to_light.y) < 0.98 else Vector3.FORWARD
	light.basis = Basis.looking_at(-to_light, up)


## Погода (значения WeatherSim.values): облачность, дымка, темнота, пыль, ветер.
func set_weather(w: Dictionary) -> void:
	_cover = float(w.get("cloud", 0.3))
	_darkness = float(w.get("darkness", 0.0))
	_fog = float(w.get("fog", 0.0))
	_dust = float(w.get("dust", 0.0))
	_rain = maxf(float(w.get("rain", 0.0)), float(w.get("hail", 0.0)))
	_snow = float(w.get("snow", 0.0))
	var wd: Vector2 = w.get("wind_dir", Vector2(0.8, 0.6))
	var ws := clampf(float(w.get("wind", 0.2)), 0.0, 1.0)
	_wind = Vector4(wd.x, wd.y, 0.25 + 0.75 * ws, ws * 1.5)
	# Цветокоррекция погоды: дождь и гроза — блёклые и холодные, туман — мягкий, суховей — тёплый.
	var wet := maxf(_rain, _snow * 0.5)
	_weather_grade = Vector4(-0.2 * wet - 0.12 * _fog - 0.15 * _cover * _cover + 0.05 * _dust,
		-0.06 * _fog + 0.04 * _darkness, -0.03 * _darkness, 0.6 * _dust - 0.25 * wet)
	sky_shader.set_shader_parameter(&"cloud_cover", _cover)
	sky_shader.set_shader_parameter(&"darkness", _darkness)
	sky_shader.set_shader_parameter(&"fog_amount", _fog + wet * 0.35)
	sky_shader.set_shader_parameter(&"dust", _dust * 0.6)
	_apply_fog_range()
	_update_lights()


## Сдвиг облаков ветром за dt секунд и положение камеры в мировых координатах (double):
## небо и тени облаков на блоках смотрят в одну и ту же точку текстуры.
func move_clouds(dt: float, cam_x: float, cam_z: float) -> void:
	var speed := 0.6 + _wind.z * 6.0
	_cloud_shift += Vector2(_wind.x, _wind.y) * speed * dt / CLOUD_TILE
	_cloud_shift = Vector2(fposmod(_cloud_shift.x, 1.0), fposmod(_cloud_shift.y, 1.0))
	var o := Vector2(fposmod(cam_x / CLOUD_TILE + _cloud_shift.x, 1.0), fposmod(cam_z / CLOUD_TILE + _cloud_shift.y, 1.0))
	sky_shader.set_shader_parameter(&"cloud_origin", o)
	var sh := _cloud_shift + _sun_shift / CLOUD_TILE
	var strength := CLOUD_SHADOW * daylight * (1.0 - smoothstep(0.6, 1.0, _cover)) if _cloud_quality > 0 else 0.0
	RenderingServer.global_shader_parameter_set(&"cloud_shadow", Vector4(fposmod(sh.x, 1.0), fposmod(sh.y, 1.0), _cover, strength))
	RenderingServer.global_shader_parameter_set(&"wind", _wind)


## Мокрость поверхностей 0…1 (лужи и блеск) — глобальный параметр шейдеров блоков.
func set_wetness(v: float, raining: float) -> void:
	RenderingServer.global_shader_parameter_set(&"rain_wetness", Vector2(v, raining))


## Вспышка молнии: небо и сцена подсвечиваются и гаснут за доли секунды.
func flash(strength: float) -> void:
	_flash = maxf(_flash, strength)


## Облака: 0 — выкл., 1 — низкое, 2 — высокое (настройка «Качество облаков»).
func set_cloud_quality(q: int) -> void:
	_cloud_quality = q
	sky_shader.set_shader_parameter(&"cloud_quality", q)


func _update_lights() -> void:
	var overcast := smoothstep(0.5, 1.0, _cover)
	var dim := (1.0 - _darkness * 0.7) * (1.0 - overcast * 0.6)
	sun.light_energy = daylight * dim
	sun.visible = daylight > 0.01
	sun.shadow_opacity = 1.0 - overcast * 0.7
	var night := 1.0 - daylight
	var mlight := moon_light * _moon_illum * _moon_up * night * (1.0 - overcast * 0.8)
	moon.light_energy = mlight
	moon.visible = mlight > 0.004
	# Ночью рассеянный свет — не только от тёмного неба, но и постоянный синеватый (луна, звёзды):
	# в полнолуние светлее, в новолуние темнее.
	var nightglow := 0.65 + 0.6 * _moon_illum
	environment.ambient_light_sky_contribution = lerpf(0.35, 1.0, daylight)
	environment.ambient_light_color = Color(0.16, 0.2, 0.32) * nightglow
	environment.ambient_light_energy = lerpf(0.5, 1.0, daylight) * (1.0 - _darkness * 0.35) + _flash * 3.0
	environment.background_energy_multiplier = 1.0
	var day_fog := Color(0.62, 0.72, 0.86).lerp(Color(0.6, 0.63, 0.66), maxf(overcast, _fog))
	day_fog = day_fog.lerp(Color(0.78, 0.68, 0.5), _dust * 0.7)
	var fc := Color(0.04, 0.05, 0.09).lerp(day_fog, daylight) * (1.0 - _darkness * 0.6)
	environment.fog_light_color = fc
	sky_shader.set_shader_parameter(&"fog_color", Vector3(fc.r, fc.g, fc.b) / maxf(0.03, daylight * (1.0 - _darkness * 0.6)))
	environment.volumetric_fog_density = 0.006 + _fog * 0.025 + _rain * 0.008 + _snow * 0.012 + _dust * 0.02
	environment.volumetric_fog_albedo = Color(0.9, 0.93, 1.0).lerp(Color(0.85, 0.74, 0.55), _dust)


func _apply_fog_range() -> void:
	var thick := clampf(_fog * 0.85 + _rain * 0.35 + _snow * 0.5 + _dust * 0.5, 0.0, 0.92)
	environment.fog_depth_begin = _fog_near * (1.0 - thick)
	environment.fog_depth_end = lerpf(_fog_far, minf(_fog_far, 90.0), thick)


## Применить качество графики (Settings.graphics) к окружению, солнцу и вьюпорту.
func apply(g: Dictionary, viewport: Viewport) -> void:
	graphics = g
	var shadow_dist: float = g.get("shadow_distance", 120.0)
	sun.shadow_enabled = shadow_dist > 0.0
	sun.directional_shadow_max_distance = maxf(shadow_dist, 1.0)
	match int(g.get("shadow_splits", 4)):
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	RenderingServer.directional_shadow_atlas_set_size(int(g.get("shadow_size", 4096)), true)
	var ssao: int = g.get("ssao", 2)
	environment.ssao_enabled = ssao > 0
	if ssao > 0:
		RenderingServer.environment_set_ssao_quality((ssao - 1) as RenderingServer.EnvironmentSSAOQuality, ssao <= 2, 0.5, 2, 50.0, 300.0)
	environment.ssil_enabled = g.get("ssil", false)
	environment.volumetric_fog_enabled = g.get("volumetric_fog", true)
	environment.glow_enabled = g.get("glow", true)
	camera_attributes.auto_exposure_enabled = g.get("auto_exposure", true)
	if viewport != null:
		var aa: StringName = StringName(g.get("anti_aliasing", "fxaa"))
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == &"fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
		viewport.use_taa = aa == &"taa"
		viewport.msaa_3d = Viewport.MSAA_2X if aa == &"msaa2" else (Viewport.MSAA_4X if aa == &"msaa4" else Viewport.MSAA_DISABLED)
		var scale: float = g.get("render_scale", 1.0)
		viewport.scaling_3d_scale = scale
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if g.get("fsr", false) and scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		if "anisotropic_filtering_level" in viewport:
			var an: int = g.get("anisotropy", 8)
			var level := Viewport.ANISOTROPY_DISABLED
			if an >= 16:
				level = Viewport.ANISOTROPY_16X
			elif an >= 8:
				level = Viewport.ANISOTROPY_8X
			elif an >= 4:
				level = Viewport.ANISOTROPY_4X
			elif an >= 2:
				level = Viewport.ANISOTROPY_2X
			viewport.set(&"anisotropic_filtering_level", level)


## Глубина резкости (настройка): размытие дальнего плана.
func set_depth_of_field(on: bool) -> void:
	camera_attributes.dof_blur_far_enabled = on
	camera_attributes.dof_blur_far_distance = 60.0
	camera_attributes.dof_blur_far_transition = 40.0
	camera_attributes.dof_blur_amount = 0.06


## Дальний туман: начинается за прорисованными чанками и прячет край LOD-рельефа.
func set_view_range(near_blocks: float, far_blocks: float) -> void:
	_fog_near = near_blocks * 0.6
	_fog_far = maxf(far_blocks, near_blocks) * 1.02
	_apply_fog_range()


## Цветокоррекция по климату биома под игроком: холод — прохладнее и бледнее, жара — теплее.
func set_biome_climate(temperature_c: float) -> void:
	var cold := clampf((5.0 - temperature_c) / 25.0, 0.0, 1.0)
	var hot := clampf((temperature_c - 22.0) / 15.0, 0.0, 1.0)
	_grade_target = Vector4(1.0 - 0.12 * cold + 0.05 * hot, 1.0 + 0.04 * hot, 1.0 + 0.03 * cold, hot - cold)


func _process(delta: float) -> void:
	_grade = _grade.lerp(_grade_target + _weather_grade, clampf(delta * GRADE_SPEED, 0.0, 1.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		sky_shader.set_shader_parameter(&"flash", _flash)
		_update_lights()
	environment.adjustment_saturation = _grade.x
	environment.adjustment_contrast = _grade.y
	environment.adjustment_brightness = _grade.z
	var warm := _grade.w
	sun.light_color = _sun_color.lerp(Color(1.0, 0.92, 0.8), maxf(warm, 0.0) * 0.5).lerp(Color(0.92, 0.96, 1.0), maxf(-warm, 0.0) * 0.5)
