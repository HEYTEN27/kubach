extends Control
## Стартовый экран: создание нового мира и загрузка сохранённых.
## Полноценное главное меню с 3D-фоном и экран создания мира с предпросмотром — этапы 2 и 4.
##
## Аргументы командной строки (после `--`) — см. GameLaunch; с --world или --bench
## игра стартует сразу, минуя меню. Здесь же:
##   --screenshot=<файл>  без --world — снимок самого меню.

const GAME_SCENE := "res://src/core/game/game.tscn"

@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _status: Label = %Status
@onready var _menu: VBoxContainer = %Menu

var _name_edit: LineEdit
var _seed_edit: LineEdit
var _mode: OptionButton
var _worlds: ItemList
var _world_list: Array[Dictionary] = []


func _ready() -> void:
	_title.text = ProjectSettings.get_setting("application/config/name")
	_info.text = "Версия %s · Godot %s · %s · %s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info()["string"],
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
	]
	_show_registry_status()
	GameLaunch.reset()
	if Registry.loaded and GameLaunch.parse_args(OS.get_cmdline_user_args()):
		_start_game.call_deferred()
		return
	_build_menu()
	_maybe_take_screenshot()


func _show_registry_status() -> void:
	var lines := PackedStringArray()
	if not Registry.loaded:
		lines.append("ОШИБКИ В ДАННЫХ (%d):" % Registry.errors.size())
		lines.append_array(Registry.errors)
	for w in Registry.warnings:
		lines.append("Предупреждение: " + w)
	_status.text = "\n".join(lines)
	_status.visible = not lines.is_empty()
	_status.modulate = Color(1.0, 0.45, 0.4)


func _build_menu() -> void:
	if not Registry.loaded:
		return
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 48)
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_child(grid)

	var create := _column(grid, "Новый мир")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Название мира"
	_name_edit.text = "Новый мир"
	create.add_child(_name_edit)
	var seed_row := HBoxContainer.new()
	create.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Сид (текст или число)"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	var rnd := Button.new()
	rnd.text = "Случайный"
	rnd.pressed.connect(func() -> void: _seed_edit.text = str(WorldSeed.random()))
	seed_row.add_child(rnd)
	_mode = OptionButton.new()
	_mode.add_item("Выживание")
	_mode.add_item("Творческий")
	create.add_child(_mode)
	var go := Button.new()
	go.text = "Создать мир"
	go.custom_minimum_size.y = 44
	go.pressed.connect(_on_create)
	create.add_child(go)

	var load := _column(grid, "Сохранённые миры")
	_worlds = ItemList.new()
	_worlds.custom_minimum_size = Vector2(360, 180)
	_worlds.item_activated.connect(func(_i: int) -> void: _on_load())
	load.add_child(_worlds)
	_world_list = WorldSave.list_worlds()
	for w in _world_list:
		_worlds.add_item("%s   (%s)" % [w["name"], String(w["last_played"]).replace("T", " ")])
	if not _world_list.is_empty():
		_worlds.select(0)
	var load_btn := Button.new()
	load_btn.text = "Загрузить"
	load_btn.custom_minimum_size.y = 44
	load_btn.disabled = _world_list.is_empty()
	load_btn.pressed.connect(_on_load)
	load.add_child(load_btn)

	var quit := Button.new()
	quit.text = "Выход"
	quit.custom_minimum_size = Vector2(200, 40)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(func() -> void: get_tree().quit())
	_menu.add_child(quit)


func _column(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 360
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 24)
	box.add_child(l)
	return box


func _on_create() -> void:
	GameLaunch.reset()
	GameLaunch.new_world_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Новый мир"
	GameLaunch.seed_text = _seed_edit.text.strip_edges() if _seed_edit.text.strip_edges() != "" else str(WorldSeed.random())
	GameLaunch.game_mode = &"creative" if _mode.selected == 1 else &"survival"
	_start_game()


func _on_load() -> void:
	var sel := _worlds.get_selected_items()
	if sel.is_empty():
		return
	GameLaunch.reset()
	GameLaunch.folder = _world_list[sel[0]]["folder"]
	_start_game()


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _maybe_take_screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			var path := arg.get_slice("=", 1)
			for i in 5:
				await RenderingServer.frame_post_draw
			var err := get_viewport().get_texture().get_image().save_png(path)
			print("Скриншот: %s (%s)" % [path, error_string(err)])
			get_tree().quit(0 if err == OK else 1)
