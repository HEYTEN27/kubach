extends GutTest
## Требования ТЗ к настройкам проекта (раздел 1 и шапка GAME_DESIGN.md).


func test_name() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Кубач")


func test_forward_plus_renderer() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "forward_plus")


func test_user_dir_is_kubach() -> void:
	assert_true(ProjectSettings.get_setting("application/config/use_custom_user_dir"))
	assert_eq(ProjectSettings.get_setting("application/config/custom_user_dir_name"), "Kubach")
	assert_true(OS.get_user_data_dir().ends_with("Kubach"), OS.get_user_data_dir())


func test_main_scene_exists() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	assert_true(ResourceLoader.exists(path), path)


func test_export_presets_produce_kubach_exe() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	assert_eq(cfg.get_value("preset.0", "platform"), "Windows Desktop")
	assert_true(String(cfg.get_value("preset.0", "export_path")).ends_with("Kubach.exe"))
	assert_string_contains(cfg.get_value("preset.0", "include_filter"), "data/*.json")
