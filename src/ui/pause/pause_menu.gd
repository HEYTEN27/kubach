class_name PauseMenu
extends CanvasLayer
## Пауза по ESC (раздел 19): продолжить, сохранить, настройки, выйти в меню, выйти из игры.

signal resume_requested
signal save_requested
signal quit_to_menu_requested
signal quit_game_requested


var _box: VBoxContainer
var _settings: SettingsScreen


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(320, 0)
	box.position -= Vector2(160, 140)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_box = box
	var title := Label.new()
	title.text = "Пауза"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	_button(box, "Продолжить", resume_requested)
	_button(box, "Сохранить", save_requested)
	var st := Button.new()
	st.text = "Настройки"
	st.custom_minimum_size = Vector2(320, 44)
	st.pressed.connect(_open_settings)
	box.add_child(st)
	_button(box, "Сохранить и выйти в меню", quit_to_menu_requested)
	_button(box, "Сохранить и выйти из игры", quit_game_requested)


func _unhandled_input(event: InputEvent) -> void:
	# Игра на паузе не получает ввод, поэтому ESC для продолжения ловит само меню.
	if visible and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		if _settings != null:
			_settings.close()
			return
		resume_requested.emit()


func _open_settings() -> void:
	_box.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_settings = SettingsScreen.new()
	center.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings = null
		center.queue_free()
		_box.visible = true)


func _button(parent: Control, text: String, sig: Signal) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(func() -> void: sig.emit())
	parent.add_child(b)
