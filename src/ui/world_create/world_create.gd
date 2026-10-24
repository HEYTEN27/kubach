extends Control
## Экран создания мира (раздел 2.2): название, сид, тип мира, ползунки, сложность, стартовый
## сезон, режим игры и предпросмотр карты биомов 512×512 (обновляется в потоке при изменениях).

const MENU_SCENE := "res://src/ui/boot/boot.tscn"
const CHARACTER_SCENE := "res://src/ui/character/character_create.tscn"
const PREVIEW_DELAY := 0.35

var _name: LineEdit
var _seed: LineEdit
var _type: OptionButton
var _type_ids: Array[StringName] = []
var _difficulty: OptionButton
var _season: OptionButton
var _mode: OptionButton
var _sliders := {}
var _preview_rect: TextureRect
var _preview_label: Label
var _preview: BiomePreview
var _preview_due := 0.0
var _preview_started_at := 0
var _hover_label: Label
var _preview_gen: TerrainGenerator


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_top = 32
	root.offset_right = -40
	root.offset_bottom = -32
	root.add_theme_constant_override("separation", 40)
	add_child(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)

	var title := Label.new()
	title.text = "Создание мира"
	title.add_theme_font_size_override("font_size", 32)
	form.add_child(title)

	_name = _line(form, "Название мира", "Новый мир")
	var seed_row := HBoxContainer.new()
	_seed = LineEdit.new()
	_seed.placeholder_text = "Текст или число; пусто — случайный"
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.text_changed.connect(func(_t: String) -> void: _schedule_preview())
	seed_row.add_child(_seed)
	var rnd := Button.new()
	rnd.text = "Случайный"
	rnd.pressed.connect(func() -> void:
		_seed.text = str(WorldSeed.random())
		_schedule_preview())
	seed_row.add_child(rnd)
	_labeled(form, "Сид", seed_row)

	_type = OptionButton.new()
	var types := Registry.get_entries("world_types")
	types.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	for t in types:
		_type.add_item(t["name"]["ru"])
		_type_ids.append(StringName(t["id"]))
	_type.item_selected.connect(func(_i: int) -> void: _schedule_preview())
	_labeled(form, "Тип мира", _type)

	_mode = _options(form, "Режим", ["Выживание", "Творческий"], 0)
	_difficulty = _options(form, "Сложность", ["Мирная", "Лёгкая", "Нормальная", "Сложная", "Хардкор (одна жизнь)"], 2)
	_season = _options(form, "Стартовый сезон", ["Весна", "Лето", "Осень", "Зима"], 1)

	_slider(form, "biome_size", "Размер биомов", 0.5, 4.0, 0.25, 1.0, "×%.2f", true)
	_slider(form, "caves", "Частота пещер", 0.0, 2.0, 0.1, 1.0, "×%.1f", false)
	_slider(form, "ores", "Обилие руд", 0.0, 3.0, 0.1, 1.0, "×%.1f", false)
	_slider(form, "sea_level", "Уровень моря", 40.0, 90.0, 1.0, 64.0, "Y = %d", true)
	_slider(form, "villages", "Деревни", 0.0, 3.0, 0.1, 1.0, "×%.1f", false)
	_slider(form, "tribe_camps", "Лагеря племён", 0.0, 3.0, 0.1, 1.0, "×%.1f", false)
	_slider(form, "bandits", "Бандиты", 0.0, 3.0, 0.1, 1.0, "×%.1f", false)
	_slider(form, "season_length", "Длина сезона", 7.0, 56.0, 1.0, 28.0, "%d дн.", false)
	_slider(form, "day_length", "Длина суток", 10.0, 60.0, 1.0, 24.0, "%d мин", false)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	form.add_child(buttons)
	var back := Button.new()
	back.text = "Назад"
	back.custom_minimum_size = Vector2(140, 44)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	buttons.add_child(back)
	var create := Button.new()
	create.text = "Создать мир"
	create.custom_minimum_size = Vector2(220, 44)
	create.pressed.connect(_on_create)
	buttons.add_child(create)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var ptitle := Label.new()
	ptitle.text = "Карта биомов (8 × 8 км вокруг точки появления)"
	right.add_child(ptitle)
	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(512, 512)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_preview_rect)
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_rect.gui_input.connect(_on_preview_input)
	_preview_label = Label.new()
	right.add_child(_preview_label)
	_hover_label = Label.new()
	_hover_label.modulate = Color(0.8, 0.85, 0.8)
	right.add_child(_hover_label)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed.text = arg.get_slice("=", 1)
	_schedule_preview(0.0)


func _exit_tree() -> void:
	if _preview != null:
		_preview.cancel()


func _process(delta: float) -> void:
	if _preview_due > 0.0:
		_preview_due -= delta
		if _preview_due <= 0.0:
			_start_preview()
	if _preview != null:
		_preview.poll()


## Настройки с формы.
func settings() -> WorldGenSettings:
	var s := WorldGenSettings.new()
	s.world_type = _type_ids[_type.selected]
	s.biome_size = _sliders["biome_size"].value
	s.caves = _sliders["caves"].value
	s.ores = _sliders["ores"].value
	s.sea_level = int(_sliders["sea_level"].value)
	s.villages = _sliders["villages"].value
	s.tribe_camps = _sliders["tribe_camps"].value
	s.bandits = _sliders["bandits"].value
	s.season_length = int(_sliders["season_length"].value)
	s.day_length = int(_sliders["day_length"].value)
	s.difficulty = WorldGenSettings.DIFFICULTIES[_difficulty.selected]
	s.start_season = WorldGenSettings.SEASONS[_season.selected]
	return s


func seed_text() -> String:
	return _seed.text.strip_edges()


func _schedule_preview(delay: float = PREVIEW_DELAY) -> void:
	_preview_due = maxf(delay, 0.001)


func _start_preview() -> void:
	if _preview != null:
		_preview.cancel()
	var text := seed_text() if seed_text() != "" else "0"
	var gen := TerrainGenerator.new(WorldSeed.from_text(text), Registry, settings())
	_preview_gen = gen
	_preview = BiomePreview.new(gen)
	_preview.level_ready.connect(_on_preview_level)
	_preview.finished.connect(func() -> void:
		_preview_label.text = "Готово за %.1f с%s" % [(Time.get_ticks_msec() - _preview_started_at) / 1000.0,
			"" if seed_text() != "" else " · сид пуст: при создании будет случайный"]
		_maybe_screenshot())
	_preview_started_at = Time.get_ticks_msec()
	_preview_label.text = "Считаю карту…"
	_preview.start()


func _on_preview_level(img: Image, size: int) -> void:
	_preview_rect.texture = ImageTexture.create_from_image(img)
	if size < BiomePreview.LEVELS[-1]:
		_preview_label.text = "Считаю карту… %d×%d" % [size, size]


## Название биома под курсором.
func _on_preview_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or _preview_gen == null or _preview == null:
		return
	var sz := _preview_rect.size
	var p: Vector2 = event.position / sz
	var x := roundi((p.x - 0.5) * _preview.span) + _preview.center.x
	var z := roundi((p.y - 0.5) * _preview.span) + _preview.center.y
	var b := _preview_gen.grid_biome(x, z)
	_hover_label.text = "%s · X %d, Z %d" % [_preview_gen.biomes.defs[b]["name"]["ru"], x, z]


func _on_create() -> void:
	GameLaunch.reset()
	GameLaunch.new_world_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Новый мир"
	GameLaunch.seed_text = seed_text() if seed_text() != "" else str(WorldSeed.random())
	GameLaunch.game_mode = &"creative" if _mode.selected == 1 else &"survival"
	GameLaunch.settings = settings().to_dict()
	get_tree().change_scene_to_file(CHARACTER_SCENE)


func _line(parent: Control, label: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	_labeled(parent, label, e)
	return e


func _options(parent: Control, label: String, items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it: String in items:
		o.add_item(it)
	o.selected = selected
	_labeled(parent, label, o)
	return o


func _slider(parent: Control, key: String, label: String, lo: float, hi: float, step: float, value: float,
		fmt: String, affects_preview: bool) -> void:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.x = 220
	var v := Label.new()
	v.custom_minimum_size.x = 80
	v.text = fmt % value
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		if affects_preview:
			_schedule_preview())
	row.add_child(s)
	row.add_child(v)
	_sliders[key] = s
	_labeled(parent, label, row)


func _labeled(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 170
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


## Смоук-тест: `godot res://src/ui/world_create/world_create.tscn -- --seed=… --screenshot=файл.png`.
func _maybe_screenshot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			for i in 3:
				await RenderingServer.frame_post_draw
			var path := arg.get_slice("=", 1)
			var err := get_viewport().get_texture().get_image().save_png(path)
			print("Скриншот: %s (%s)" % [path, error_string(err)])
			get_tree().quit()
