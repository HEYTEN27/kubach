class_name ScreenshotUtil
extends RefCounted
## Снимок кадра для визуальных смоук-тестов (scripts/screenshot.sh): аргумент --screenshot=<png>.


## Путь из аргументов или пустая строка.
static func requested_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			return arg.get_slice("=", 1)
	return ""


## Подождать frames кадров, сохранить кадр и выйти из игры.
static func capture_and_quit(node: Node, path: String, frames: int = 8) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
	var err := node.get_viewport().get_texture().get_image().save_png(path)
	print("Скриншот: %s (%s)" % [path, error_string(err)])
	node.get_tree().quit(0 if err == OK else 1)
