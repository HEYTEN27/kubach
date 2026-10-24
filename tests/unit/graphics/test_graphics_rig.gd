extends GutTest
## Окружение: пресеты включают и выключают эффекты, туман следует за дальностью.

var rig: GraphicsRig


func before_each() -> void:
	rig = GraphicsRig.new()
	add_child_autofree(rig)


func test_low_preset_disables_expensive_effects() -> void:
	rig.apply(GameSettings.preset_values(Registry, &"low"), null)
	assert_false(rig.environment.ssao_enabled)
	assert_false(rig.environment.ssil_enabled)
	assert_false(rig.environment.volumetric_fog_enabled)
	assert_false(rig.environment.glow_enabled)
	assert_eq(rig.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)


func test_ultra_preset_enables_everything() -> void:
	rig.apply(GameSettings.preset_values(Registry, &"ultra"), null)
	assert_true(rig.environment.ssao_enabled)
	assert_true(rig.environment.ssil_enabled)
	assert_true(rig.environment.volumetric_fog_enabled)
	assert_true(rig.camera_attributes.auto_exposure_enabled)
	assert_eq(rig.environment.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_eq(rig.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_eq(rig.sun.directional_shadow_max_distance, 180.0)


func test_fog_follows_view_range() -> void:
	rig.set_view_range(192.0, 512.0)
	assert_lt(rig.environment.fog_depth_begin, 192.0)
	assert_gt(rig.environment.fog_depth_end, 512.0)


func test_cold_biome_is_less_saturated() -> void:
	rig.set_biome_climate(-20.0)
	for i in 30:
		rig._process(0.5)
	assert_lt(rig.environment.adjustment_saturation, 0.95)
	rig.set_biome_climate(30.0)
	for i in 30:
		rig._process(0.5)
	assert_gt(rig.environment.adjustment_saturation, 1.0)
