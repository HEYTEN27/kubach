class_name GraphicsRig
extends Node3D
## Окружение и настройки графики (этап 3, раздел 16 ТЗ): атмосферное небо с рассеянием,
## солнце с каскадными тенями, SSAO/SSIL, объёмный и дальний туман, glow, тонмаппинг AgX,
## автоэкспозиция (выход из пещеры ослепляет), цветокоррекция по климату биома.
## Значения качества — из Settings.graphics (data/graphics_presets.json).
##
## Базовая смена суток (этап 5): солнце идёт по дуге по часам GameClock, ночью гаснет, небо
## и рассеянный свет темнеют. Луна с фазами, звёзды и длина дня по сезону — этап 7.

const SUN_ROTATION := Vector3(-48.0, -35.0, 0.0)
## Скорость смены цветокоррекции при переходе между биомами (доля за секунду).
const GRADE_SPEED := 0.6

var environment: Environment
var sun: DirectionalLight3D
## Лунный свет: тусклый холодный, ночью вместо солнца (фазы луны — этап 7).
var moon: DirectionalLight3D
var camera_attributes: CameraAttributesPractical
var sky_material: PhysicalSkyMaterial
var world_environment: WorldEnvironment
var graphics := {}

var _grade_target := Vector4(1.0, 1.0, 1.0, 0.0)   # насыщенность, контраст, яркость, теплота
var _grade := Vector4(1.0, 1.0, 1.0, 0.0)
## Дневной свет 0 (ночь) … 1 (день) — для неба, солнца и рассеянного света.
var daylight := 1.0
var _sun_color := Color(1.0, 0.97, 0.92)


func _init() -> void:
	name = "GraphicsRig"
	sky_material = PhysicalSkyMaterial.new()
	sky_material.rayleigh_coefficient = 2.2
	sky_material.mie_coefficient = 0.004
	sky_material.mie_eccentricity = 0.82
	sky_material.turbidity = 8.0
	# Низ неба — цвет дымки: за краем LOD-рельефа не видно тёмной полосы.
	sky_material.ground_color = Color(0.55, 0.62, 0.7)
	sky_material.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# Запасной рендер (OpenGL 3): физическое небо там рисуется неверно — процедурное.
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.26, 0.45, 0.75)
		proc.sky_horizon_color = Color(0.66, 0.76, 0.88)
		proc.ground_horizon_color = Color(0.66, 0.76, 0.88)
		proc.ground_bottom_color = Color(0.6, 0.68, 0.78)
		proc.ground_curve = 0.5
		sky.sky_material = proc
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
	sun.rotation_degrees = SUN_ROTATION
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


## Положение солнца по часу суток (0…24): восход в 6:00, закат в 21:00, полдень ~13:30.
func set_time_of_day(hour: float) -> void:
	const RISE := 6.0
	const SET := 21.0
	var t := (hour - RISE) / (SET - RISE)   # 0…1 — день
	var elev: float
	if t >= 0.0 and t <= 1.0:
		elev = sin(t * PI) * 62.0
	else:
		# Ночь: солнце под горизонтом.
		var n := fposmod(hour - SET, 24.0) / (24.0 - (SET - RISE))
		elev = -sin(n * PI) * 30.0
	var azimuth := -90.0 + clampf(t, -0.2, 1.2) * 180.0
	sun.rotation_degrees = Vector3(-elev, azimuth + SUN_ROTATION.y, 0.0)
	daylight = smoothstep(-6.0, 8.0, elev)
	var low := 1.0 - smoothstep(4.0, 22.0, elev)   # закатный тёплый свет
	_sun_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.62, 0.36), low * daylight)
	sun.light_energy = daylight
	sun.visible = daylight > 0.01
	var night := 1.0 - daylight
	moon.visible = night > 0.01
	moon.light_energy = 0.16 * night
	moon.rotation_degrees = Vector3(-50.0, sun.rotation_degrees.y + 180.0, 0.0)
	# Ночью рассеянный свет — не только от тёмного неба, но и постоянный синеватый (луна, звёзды).
	environment.ambient_light_sky_contribution = lerpf(0.35, 1.0, daylight)
	environment.ambient_light_color = Color(0.16, 0.2, 0.32)
	environment.ambient_light_energy = lerpf(0.55, 1.0, daylight)
	environment.background_energy_multiplier = lerpf(0.12, 1.0, daylight)
	environment.fog_light_color = Color(0.05, 0.07, 0.12).lerp(Color(0.62, 0.72, 0.86), daylight)


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
	environment.fog_depth_begin = near_blocks * 0.6
	environment.fog_depth_end = maxf(far_blocks, near_blocks) * 1.02


## Цветокоррекция по климату биома под игроком: холод — прохладнее и бледнее, жара — теплее.
func set_biome_climate(temperature_c: float) -> void:
	var cold := clampf((5.0 - temperature_c) / 25.0, 0.0, 1.0)
	var hot := clampf((temperature_c - 22.0) / 15.0, 0.0, 1.0)
	_grade_target = Vector4(1.0 - 0.12 * cold + 0.05 * hot, 1.0 + 0.04 * hot, 1.0 + 0.03 * cold, hot - cold)


func _process(delta: float) -> void:
	_grade = _grade.lerp(_grade_target, clampf(delta * GRADE_SPEED, 0.0, 1.0))
	environment.adjustment_saturation = _grade.x
	environment.adjustment_contrast = _grade.y
	environment.adjustment_brightness = _grade.z
	var warm := _grade.w
	sun.light_color = _sun_color.lerp(Color(1.0, 0.92, 0.8), maxf(warm, 0.0) * 0.5).lerp(Color(0.92, 0.96, 1.0), maxf(-warm, 0.0) * 0.5)
