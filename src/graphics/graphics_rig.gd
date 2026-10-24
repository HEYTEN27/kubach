class_name GraphicsRig
extends Node3D
## Окружение и настройки графики (этап 3, раздел 16 ТЗ): атмосферное небо с рассеянием,
## солнце с каскадными тенями, SSAO/SSIL, объёмный и дальний туман, glow, тонмаппинг AgX,
## автоэкспозиция (выход из пещеры ослепляет), цветокоррекция по климату биома.
## Значения качества — из Settings.graphics (data/graphics_presets.json).
##
## Смена суток и луна — этап 5 (время и сезоны); сейчас солнце стоит в утреннем положении.

const SUN_ROTATION := Vector3(-48.0, -35.0, 0.0)
## Скорость смены цветокоррекции при переходе между биомами (доля за секунду).
const GRADE_SPEED := 0.6

var environment: Environment
var sun: DirectionalLight3D
var camera_attributes: CameraAttributesPractical
var sky_material: PhysicalSkyMaterial
var world_environment: WorldEnvironment
var graphics := {}

var _grade_target := Vector4(1.0, 1.0, 1.0, 0.0)   # насыщенность, контраст, яркость, теплота
var _grade := Vector4(1.0, 1.0, 1.0, 0.0)


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
	sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.92, 0.8), maxf(warm, 0.0)).lerp(Color(0.92, 0.96, 1.0), maxf(-warm, 0.0))
