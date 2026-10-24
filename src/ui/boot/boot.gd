extends Control
## Главное меню (раздел 19 ТЗ): живая 3D-сцена тайги на фоне (камера медленно облетает
## поляну), пункты «Продолжить», «Новая игра», «Загрузить», «Настройки», «Достижения»,
## «Титры», «Выход». Смена погоды на фоне появится вместе с погодой (этап 7).
##
## Аргументы командной строки (после `--`) — см. GameLaunch; с --world или --bench игра
## стартует сразу, минуя меню. Здесь же:
##   --screenshot=<файл>  без --world — снимок самого меню;
##   --menu=load|settings|credits|character — сразу открыть панель или редактор персонажа
##   (для скриншотов и проверки).

const GAME_SCENE := "res://src/core/game/game.tscn"
const CREATE_SCENE := "res://src/ui/world_create/world_create.tscn"
const MENU_SEED := "тайга"
const BG_VIEW := 6

@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _status: Label = %Status
@onready var _menu: VBoxContainer = %Menu

var _world_list: Array[Dictionary] = []
var _panel_holder: Control
var _panel: Control
var _bg_world: World
var _bg_cam: Camera3D
var _bg_center := Vector2i.ZERO
var _bg_target := Vector3.ZERO
var _bg_angle := 0.0


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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Registry.loaded:
		_build_background()
	_build_menu()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu="):
			match arg.get_slice("=", 1):
				"load":
					_open_load()
				"settings":
					_open_settings()
				"credits":
					_open_credits()
				"character":
					get_tree().change_scene_to_file.call_deferred("res://src/ui/character/character_create.tscn")
					return
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


# ---------------------------------------------------------------------------------------------
# Фон: настоящий мир по сиду, камера кружит над тайгой

func _build_background() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	move_child(holder, 1)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	holder.add_child(vp)
	var rig := GraphicsRig.new()
	vp.add_child(rig)
	var g := Settings.graphics.duplicate()
	g["volumetric_fog"] = true
	rig.apply(g, null)
	_bg_world = World.new()
	_bg_world.setup(Registry, null, WorldSeed.from_text(MENU_SEED))
	_bg_world.chunks.view_distance = BG_VIEW
	vp.add_child(_bg_world)
	var far := FarTerrain.new()
	_bg_world.add_child(far)
	far.setup(_bg_world, _bg_world.chunks.season)
	far.configure(true, 24, (BG_VIEW - 2.5) * 16.0)
	rig.set_view_range(BG_VIEW * 16.0, 24 * 16.0)
	if ScreenshotUtil.requested_path() != "":
		# Программный OpenGL рисует кадр секундами — раздаём задачи пачками.
		var ch := _bg_world.chunks
		ch.apply_budget_usec = 200000
		ch.max_mesh_in_flight = 256
		ch.max_light_in_flight = 32
		ch.max_gen_in_flight = 16
		far.max_in_flight = 16
	var spot := _find_taiga()
	_bg_center = Vector2i(spot.x >> 4, spot.y >> 4)
	var h := maxi(_bg_world.generator.surface_height(spot.x, spot.y), _bg_world.generator.sea_level)
	_bg_target = Vector3(spot.x, h + 3, spot.y)
	_bg_world.update_origin(spot.x, h, spot.y)
	_bg_cam = Camera3D.new()
	_bg_cam.fov = 60
	_bg_cam.far = 1200
	vp.add_child(_bg_cam)
	_bg_cam.current = true
	_bg_angle = 0.6
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.25)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 2)
	set_meta("far", far)


func _find_taiga() -> Vector2i:
	var gen := _bg_world.generator
	var taiga := gen.biomes.index_of(&"taiga")
	for r in range(0, 4000, 64):
		var n := maxi(1, r / 32)
		for i in n:
			var a := TAU * i / n
			var x := roundi(cos(a) * r)
			var z := roundi(sin(a) * r)
			if gen.grid_biome(x, z) == taiga and gen.surface_height(x, z) > gen.sea_level + 2:
				return Vector2i(x, z)
	return Vector2i.ZERO


func _process(delta: float) -> void:
	if _bg_world == null:
		return
	_bg_world.chunks.update(_bg_center)
	(get_meta("far") as FarTerrain).update(_bg_center.x * 16.0 + 8.0, _bg_center.y * 16.0 + 8.0)
	_bg_angle += delta * 0.03
	var r := 30.0
	var p := Vector3(_bg_target.x + cos(_bg_angle) * r, _bg_target.y + 11.0, _bg_target.z + sin(_bg_angle) * r)
	var o := Vector3(_bg_world.origin)
	_bg_cam.look_at_from_position(p - o, _bg_target - o)


# ---------------------------------------------------------------------------------------------
# Меню и панели

func _build_menu() -> void:
	if not Registry.loaded:
		return
	_world_list = WorldSave.list_worlds()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 320
	row.add_child(col)
	var cont := _button(col, "Продолжить", _continue)
	cont.disabled = _world_list.is_empty()
	if not _world_list.is_empty():
		cont.tooltip_text = "Последний мир: %s" % _world_list[0]["name"]
	_button(col, "Новая игра", func() -> void: get_tree().change_scene_to_file(CREATE_SCENE))
	_button(col, "Загрузить", _open_load).disabled = _world_list.is_empty()
	_button(col, "Настройки", _open_settings)
	_button(col, "Достижения", _open_achievements)
	_button(col, "Титры", _open_credits)
	_button(col, "Выход", func() -> void: get_tree().quit())
	_panel_holder = CenterContainer.new()
	_panel_holder.custom_minimum_size = Vector2(0, 0)
	row.add_child(_panel_holder)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func() -> void:
		Audio.play_ui("ui/click")
		cb.call())
	parent.add_child(b)
	return b


func _show_panel(p: Control) -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = p
	_panel_holder.add_child(p)


func _continue() -> void:
	if _world_list.is_empty():
		return
	GameLaunch.reset()
	GameLaunch.folder = _world_list[0]["folder"]
	_start_game()


func _open_load() -> void:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var t := Label.new()
	t.text = "Сохранённые миры"
	t.add_theme_font_size_override("font_size", 24)
	box.add_child(t)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(640, 420)
	list.fixed_icon_size = Vector2i(160, 90)
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.max_text_lines = 3
	list.auto_height = false
	list.same_column_width = true
	list.fixed_column_width = 600
	box.add_child(list)
	_world_list = WorldSave.list_worlds()
	for w in _world_list:
		var icon: Texture2D = null
		if FileAccess.file_exists(w["preview"]):
			var img := Image.load_from_file(ProjectSettings.globalize_path(w["preview"]))
			if img != null and not img.is_empty():
				icon = ImageTexture.create_from_image(img)
		var secs := int(w["play_time_sec"])
		var text := "%s\n%s · в игре %d ч %02d мин · %s, день %d\n%s" % [w["name"],
			"творческий" if w["game_mode"] == "creative" else "выживание", secs / 3600, (secs / 60) % 60,
			{ "spring": "весна", "summer": "лето", "autumn": "осень", "winter": "зима" }.get(String(w["season"]), w["season"]),
			w["day"], String(w["last_played"]).replace("T", " ")]
		list.add_item(text, icon)
	if not _world_list.is_empty():
		list.select(0)
	list.item_activated.connect(func(i: int) -> void: _load_index(i))
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var load_btn := Button.new()
	load_btn.text = "Загрузить"
	load_btn.pressed.connect(func() -> void:
		var sel := list.get_selected_items()
		if not sel.is_empty():
			_load_index(sel[0]))
	buttons.add_child(load_btn)
	var del := Button.new()
	del.text = "Удалить…"
	del.pressed.connect(func() -> void:
		var sel := list.get_selected_items()
		if sel.is_empty():
			return
		var w: Dictionary = _world_list[sel[0]]
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Удалить мир «%s» без возможности восстановления?" % w["name"]
		dlg.ok_button_text = "Удалить"
		dlg.cancel_button_text = "Отмена"
		dlg.confirmed.connect(func() -> void:
			WorldSave.delete_world(w["folder"])
			_open_load())
		add_child(dlg)
		dlg.popup_centered())
	buttons.add_child(del)
	_show_panel(panel)


func _load_index(i: int) -> void:
	GameLaunch.reset()
	GameLaunch.folder = _world_list[i]["folder"]
	_start_game()


func _open_settings() -> void:
	var s := SettingsScreen.new()
	s.closed.connect(func() -> void: _panel = null)
	_show_panel(s)


func _open_achievements() -> void:
	_show_panel(_text_panel("Достижения", "Достижения, журнал и бестиарий появятся вместе с прогрессией (этап 15).\n" +
		"Сейчас здесь пусто — играйте, их отметки позже начнутся с нуля."))


func _open_credits() -> void:
	var lines := PackedStringArray([
		"[b]Кубач[/b] — блочная песочница-выживание.",
		"",
		"[b]Движок[/b]: Godot Engine %s (MIT) — godotengine.org" % Engine.get_version_info()["string"],
		"[b]Тесты[/b]: GUT 9 (MIT)",
		"[b]Текстуры и иконки[/b]: процедурные, tools/texgen (исходники в репозитории)",
		"[b]Шрифт интерфейса[/b]: встроенный шрифт Godot",
		"",
		"[b]Звуки и музыка[/b]: только настоящие записи; список источников и лицензий — assets/audio/CREDITS.md.",
	])
	var credits := FileAccess.get_file_as_string("res://assets/audio/CREDITS.md")
	var rows := 0
	for l in credits.split("\n"):
		if l.begins_with("|") and not l.contains("---") and not l.contains("Файл") and not l.contains("| — |"):
			lines.append(l.replace("|", " · ").strip_edges())
			rows += 1
	if rows == 0:
		lines.append("Записей пока нет: аудиофайлы ещё не добавлены (см. assets/audio/MANIFEST.md).")
	_show_panel(_text_panel("Титры", "\n".join(lines)))


func _text_panel(title: String, text: String) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	box.add_child(t)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = text
	rt.custom_minimum_size = Vector2(620, 360)
	box.add_child(rt)
	return panel


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _maybe_take_screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			var path := arg.get_slice("=", 1)
			# Ждём, пока фон догрузится (не дольше 180 с).
			var t0 := Time.get_ticks_msec()
			while _bg_world != null and Time.get_ticks_msec() - t0 < 180000:
				var ch := _bg_world.chunks
				if ch.columns.size() > 20 and ch.pending_generation() == 0 and ch.pending_meshing() == 0 \
						and (get_meta("far") as FarTerrain).pending() == 0:
					break
				await get_tree().process_frame
			for i in 8:
				await RenderingServer.frame_post_draw
			if _bg_world != null:
				print("Фон: колонн %d, мешей %d, LOD-плиток %d" % [_bg_world.chunks.columns.size(),
					_bg_world.chunks.mesh_node_count(), (get_meta("far") as FarTerrain).tile_count()])
			var err := get_viewport().get_texture().get_image().save_png(path)
			print("Скриншот: %s (%s)" % [path, error_string(err)])
			get_tree().quit(0 if err == OK else 1)
