extends Control
## Создание персонажа (раздел 4.2 ТЗ): тип тела, рост, телосложение, кожа, лицо (готовые лица
## и отдельно глаза, брови, нос, рот, цвет глаз), причёска (18), цвет волос, борода, шрамы,
## стартовая одежда и её цвета. Модель видна в 3D и вращается мышью. Варианты — из data/.
## Сменить внешность позже можно будет у цирюльника (этап 12).

const GAME_SCENE := "res://src/core/game/game.tscn"
const CREATE_SCENE := "res://src/ui/world_create/world_create.tscn"
const OUTFIT_CHOICES := {
	"body": [&"linen_shirt", &"leather_jacket", &"fur_coat"],
	"legs": [&"linen_pants", &"leather_pants"],
	"feet": [&"bast_shoes", &"leather_boots", &"valenki"],
}

var appearance := {}
var outfit := { "body": { "id": "linen_shirt", "color": "#d8ccb0" }, "legs": { "id": "linen_pants", "color": "#b8ac90" },
	"feet": { "id": "bast_shoes", "color": "#b89a5a" } }

var _preview: CharacterPreview
var _equip: Inventory
var _controls := {}
var _rng := RandomNumberGenerator.new()
var _updating := false


func _ready() -> void:
	appearance = CharacterModel.default_appearance()
	if not GameLaunch.appearance.is_empty():
		appearance.merge(GameLaunch.appearance, true)
	_rng.randomize()
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.085)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_top = 30
	root.offset_right = -40
	root.offset_bottom = -30
	root.add_theme_constant_override("separation", 30)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var title := Label.new()
	title.text = "Создание персонажа"
	title.add_theme_font_size_override("font_size", 32)
	left.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)

	_section(form, "Тело")
	_option(form, "Тип тела", "body", "body_types")
	_slider(form, "Рост", "height", 0.9, 1.1, 0.01)
	_slider(form, "Телосложение", "build", 0.0, 1.0, 0.01)
	_palette(form, "Цвет кожи", "skin", "skin")
	_section(form, "Лицо")
	_preset_option(form)
	_part_option(form, "Глаза", "eyes")
	_palette(form, "Цвет глаз", "eye_color", "eyes")
	_part_option(form, "Брови", "brows")
	_part_option(form, "Нос", "nose")
	_part_option(form, "Рот", "mouth")
	_scars(form)
	_section(form, "Волосы")
	_option(form, "Причёска", "hair", "hairstyles")
	_palette(form, "Цвет волос", "hair_color", "hair")
	_option(form, "Борода и усы", "beard", "beards")
	_section(form, "Стартовая одежда")
	for slot: String in ["body", "legs", "feet"]:
		_outfit_row(form, slot)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)
	_equip = Inventory.new(Registry, PlayerInventory.EQUIP_KINDS.size(), "preview")
	_preview = CharacterPreview.new(Vector2i(420, 620))
	_preview.setup(Registry, appearance, _equip)
	right.add_child(_preview)
	var hint := Label.new()
	hint.text = "Потяните модель, чтобы повернуть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	right.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	right.add_child(buttons)
	var back := Button.new()
	back.text = "Назад"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(CREATE_SCENE))
	buttons.add_child(back)
	var rnd := Button.new()
	rnd.text = "Случайно"
	rnd.pressed.connect(_randomize)
	buttons.add_child(rnd)
	var go := Button.new()
	go.text = "Начать игру"
	go.custom_minimum_size.x = 200
	go.pressed.connect(_start)
	buttons.add_child(go)
	_refresh()
	var shot := ScreenshotUtil.requested_path()
	if shot != "":
		_preview.auto_rotate = 0.0
		ScreenshotUtil.capture_and_quit(self, shot, 12)


func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", UiTheme.accent())
	parent.add_child(l)


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 190
	row.add_child(l)
	parent.add_child(row)
	return row


func _option(parent: Control, text: String, key: String, category: String) -> void:
	var row := _row(parent, text)
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = 260
	var entries := Registry.get_entries(category)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("order", 0) < b.get("order", 0))
	for e in entries:
		ob.add_item(String(e["name"]["ru"]))
		ob.set_item_metadata(ob.item_count - 1, String(e["id"]))
	ob.item_selected.connect(func(i: int) -> void: _apply_value(key, ob.get_item_metadata(i)))
	_arrows(row, ob)
	_controls[key] = ob


func _arrows(row: HBoxContainer, ob: OptionButton) -> void:
	var prev := Button.new()
	prev.text = "◀"
	prev.pressed.connect(func() -> void:
		ob.select(posmod(ob.selected - 1, ob.item_count))
		ob.item_selected.emit(ob.selected))
	var next := Button.new()
	next.text = "▶"
	next.pressed.connect(func() -> void:
		ob.select(posmod(ob.selected + 1, ob.item_count))
		ob.item_selected.emit(ob.selected))
	row.add_child(prev)
	row.add_child(ob)
	row.add_child(next)


func _part_option(parent: Control, text: String, part: String) -> void:
	var row := _row(parent, text)
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = 260
	for e in Registry.get_entries("face_parts"):
		if String(e["part"]) == part:
			ob.add_item(String(e["name"]["ru"]))
			ob.set_item_metadata(ob.item_count - 1, String(e["id"]))
	ob.item_selected.connect(func(i: int) -> void: _apply_value(part, ob.get_item_metadata(i)))
	_arrows(row, ob)
	_controls[part] = ob


func _preset_option(parent: Control) -> void:
	var row := _row(parent, "Лицо (готовое)")
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = 260
	for e in Registry.get_entries("face_presets"):
		ob.add_item(String(e["name"]["ru"]))
		ob.set_item_metadata(ob.item_count - 1, String(e["id"]))
	ob.item_selected.connect(func(i: int) -> void:
		var p := Registry.get_entry("face_presets", StringName(ob.get_item_metadata(i)))
		appearance["face"] = String(p["id"])
		for k in ["eyes", "brows", "nose", "mouth"]:
			appearance[k] = String(p[k])
		_refresh())
	_arrows(row, ob)
	_controls["face"] = ob


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := _row(parent, text)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.custom_minimum_size.x = 300
	sl.value_changed.connect(func(v: float) -> void: _apply_value(key, v))
	row.add_child(sl)
	_controls[key] = sl


func _palette(parent: Control, text: String, key: String, palette: String, target: Dictionary = {}) -> void:
	var row := _row(parent, text)
	var cols: Array = Registry.get_entry("palettes", StringName(palette)).get("colors", [])
	for c: Color in cols:
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		var sb := UiTheme.box(c, Color(0, 0, 0, 0.6), 2, 4, 0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UiTheme.box(c, UiTheme.accent(), 3, 4, 0))
		b.add_theme_stylebox_override("pressed", UiTheme.box(c, Color.WHITE, 3, 4, 0))
		b.tooltip_text = c.to_html(false)
		b.pressed.connect(func() -> void:
			if target.is_empty():
				_apply_value(key, "#" + c.to_html(false))
			else:
				target[key] = "#" + c.to_html(false)
				_refresh())
		row.add_child(b)


func _scars(parent: Control) -> void:
	var row := _row(parent, "Шрамы")
	for e in Registry.get_entries("face_parts"):
		if String(e["part"]) != "scar":
			continue
		var cb := CheckBox.new()
		cb.text = String(e["name"]["ru"])
		var id := String(e["id"])
		cb.toggled.connect(func(on: bool) -> void:
			var scars: Array = appearance.get("scars", []).duplicate()
			scars.erase(id)
			if on:
				scars.append(id)
			_apply_value("scars", scars))
		_controls["scar_" + id] = cb
		row.add_child(cb)


func _outfit_row(parent: Control, slot: String) -> void:
	var names := { "body": "Верх", "legs": "Низ", "feet": "Обувь" }
	var row := _row(parent, names[slot])
	var ob := OptionButton.new()
	ob.custom_minimum_size.x = 220
	for id: StringName in OUTFIT_CHOICES[slot]:
		ob.add_item(Registry.item(id).display_name())
		ob.set_item_metadata(ob.item_count - 1, String(id))
	ob.item_selected.connect(func(i: int) -> void:
		outfit[slot]["id"] = ob.get_item_metadata(i)
		_refresh())
	row.add_child(ob)
	_controls["outfit_" + slot] = ob
	_palette(parent, "   цвет", "color", "cloth", outfit[slot])


func _apply_value(key: String, value: Variant) -> void:
	if _updating:
		return
	appearance[key] = value
	_refresh()


func _randomize() -> void:
	appearance = CharacterModel.random_appearance(Registry, _rng)
	var cloth: Array = Registry.get_entry("palettes", &"cloth").get("colors", [Color.GRAY])
	for slot: String in OUTFIT_CHOICES:
		var ids: Array = OUTFIT_CHOICES[slot]
		outfit[slot]["id"] = String(ids[_rng.randi() % ids.size()])
		outfit[slot]["color"] = "#" + (cloth[_rng.randi() % cloth.size()] as Color).to_html(false)
	_refresh()


func _refresh() -> void:
	_updating = true
	for key: String in _controls:
		var c: Control = _controls[key]
		if c is OptionButton:
			var want := ""
			if key.begins_with("outfit_"):
				want = String(outfit[key.substr(7)]["id"])
			else:
				want = String(appearance.get(key, ""))
			for i in (c as OptionButton).item_count:
				if String((c as OptionButton).get_item_metadata(i)) == want:
					(c as OptionButton).select(i)
		elif c is HSlider:
			(c as HSlider).value = float(appearance.get(key, 0.5))
		elif c is CheckBox:
			(c as CheckBox).button_pressed = (appearance.get("scars", []) as Array).has(key.substr(5))
	_updating = false
	# Одежда на модели — те же предметы, что окажутся в экипировке.
	for i in _equip.size():
		_equip.slots[i] = null
	for slot: String in outfit:
		var st := ItemStack.create(Registry.item(StringName(outfit[slot]["id"])))
		st.data["color"] = outfit[slot]["color"]
		_equip.slots[PlayerInventory.EQUIP_KINDS.find(StringName(slot))] = st
	_preview.model.set_appearance(appearance)
	_preview.model.set_equipment(_equip)


func _start() -> void:
	GameLaunch.appearance = appearance.duplicate(true)
	var arr := []
	for slot: String in outfit:
		arr.append(outfit[slot].duplicate())
	GameLaunch.outfit = arr
	get_tree().change_scene_to_file(GAME_SCENE)
