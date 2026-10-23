extends Control
## Стартовый экран этапа 0: показывает, что проект собран и данные загружены.
## На этапе 4 его заменит главное меню.
##
## Аргументы командной строки (после `--`):
##   --bench=<сек>         — записать frametime в user://bench/ и выйти;
##   --screenshot=<файл>   — сохранить кадр в PNG и выйти (визуальный смоук-тест в облаке
##                           под xvfb-run; там рендер программный, через OpenGL 3).

@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _status: Label = %Status


func _ready() -> void:
	_title.text = ProjectSettings.get_setting("application/config/name")
	_info.text = "Версия %s · Godot %s · %s · %s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info()["string"],
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
	]
	_show_registry_status()
	_maybe_start_bench()
	_maybe_take_screenshot()


func _show_registry_status() -> void:
	var lines := PackedStringArray()
	if Registry.loaded:
		lines.append("Данные загружены: %d блоков (с воздухом), категории: %s" % [
			Registry.block_count(), ", ".join(Registry.categories())])
	else:
		lines.append("ОШИБКИ В ДАННЫХ (%d):" % Registry.errors.size())
		lines.append_array(Registry.errors)
	for w in Registry.warnings:
		lines.append("Предупреждение: " + w)
	_status.text = "\n".join(lines)
	_status.modulate = Color.WHITE if Registry.loaded else Color(1.0, 0.45, 0.4)


func _maybe_start_bench() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench="):
			var logger := FrameTimeLogger.new()
			logger.label = "boot"
			logger.duration_sec = maxf(1.0, arg.get_slice("=", 1).to_float())
			logger.finished.connect(func(_s: Dictionary) -> void: get_tree().quit())
			add_child(logger)


func _maybe_take_screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			var path := arg.get_slice("=", 1)
			# Несколько кадров, чтобы контейнеры успели разложиться.
			for i in 5:
				await RenderingServer.frame_post_draw
			var err := get_viewport().get_texture().get_image().save_png(path)
			print("Скриншот: %s (%s)" % [path, error_string(err)])
			get_tree().quit(0 if err == OK else 1)
