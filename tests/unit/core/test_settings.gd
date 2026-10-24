extends GutTest
## Настройки графики: пресеты из data/, «Свои», сохранение.

const TMP := "user://test_settings.cfg"


func after_each() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_four_presets_in_order() -> void:
	var ids := GameSettings.preset_ids(Registry)
	assert_eq(ids, [&"low", &"medium", &"high", &"ultra"] as Array[StringName])


func test_presets_scale_up() -> void:
	var low := GameSettings.preset_values(Registry, &"low")
	var ultra := GameSettings.preset_values(Registry, &"ultra")
	assert_lt(low["view_distance"], ultra["view_distance"])
	assert_lt(low["shadow_distance"], ultra["shadow_distance"])
	assert_false(low["dense_grass"], "на «Низких» плотной травы нет")
	assert_true(ultra["ssil"], "SSIL — только «Ультра»")
	assert_false(low.has("id"), "служебные поля убраны")


func test_high_is_target_preset() -> void:
	# Раздел 20: GTX 1660 — «Высокие», дальность 12 чанков.
	assert_eq(GameSettings.preset_values(Registry, &"high")["view_distance"], 12)


func test_custom_override_and_save() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	s.set_preset(&"medium")
	s.set_graphics("ssao", 0)
	assert_eq(s.preset, GameSettings.CUSTOM)
	assert_eq(s.graphics["ssao"], 0)
	assert_eq(s.graphics["view_distance"], 8, "остальное — от пресета, с которого начали")
	assert_eq(s.save_settings(TMP), OK)
	var s2 := GameSettings.new()
	add_child_autofree(s2)
	s2.load_settings(TMP)
	assert_eq(s2.preset, GameSettings.CUSTOM)
	assert_eq(s2.graphics["ssao"], 0)
	assert_eq(s2.graphics["view_distance"], 8)


func test_unknown_preset_falls_back() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	s.set_preset(&"nope")
	assert_eq(s.graphics["view_distance"], 12, "неизвестный пресет → «Высокие»")


func test_all_sections_have_settings() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	for sec in ["graphics", "display", "audio", "controls", "interface", "accessibility", "gameplay"]:
		assert_gt(s.definitions(sec).size(), 0, sec)


func test_defaults_and_values() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	s.load_settings(TMP)
	assert_eq(s.get_value("fov"), 75)
	assert_eq(s.get_value("show_fps"), false)
	assert_eq(s.get_value("crosshair_style"), "cross")
	s.set_value("fov", 90)
	assert_eq(s.get_value("fov"), 90)
	assert_eq(s.save_settings(TMP), OK)
	var s2 := GameSettings.new()
	add_child_autofree(s2)
	s2.load_settings(TMP)
	assert_eq(s2.get_value("fov"), 90)


func test_graphics_setting_goes_through_preset() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	s.set_preset(&"high")
	assert_eq(s.get_value("view_distance"), 12)
	s.set_value("view_distance", 20)
	assert_eq(s.preset, GameSettings.CUSTOM)
	assert_eq(s.graphics["view_distance"], 20)
	s.set_value("graphics_preset", "low")
	assert_eq(s.get_value("view_distance"), 6)


func test_reset_section() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	s.set_value("hud_opacity", 0.4)
	s.reset_section("interface")
	assert_almost_eq(float(s.get_value("hud_opacity")), 1.0, 0.001)


func test_every_setting_definition_is_consistent() -> void:
	var s := GameSettings.new()
	add_child_autofree(s)
	for d in s.definitions():
		var v: Variant = s.default_value(String(d["id"]))
		match String(d["type"]):
			"enum":
				var vals := []
				for o: Dictionary in d["options"]:
					vals.append(String(o["value"]))
				assert_has(vals, String(v), "%s: значение по умолчанию среди вариантов" % d["id"])
			"int", "float":
				assert_between(float(v), float(d["min"]), float(d["max"]), String(d["id"]))
