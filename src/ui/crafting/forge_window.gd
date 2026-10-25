class_name ForgeWindow
extends CanvasLayer
## Мини-игра ковки (раздел 5.3 ТЗ): заготовка из 8 столбиков, контур — нужная форма.
## ЛКМ по столбику — вытяжка (опускает его, металл уходит к соседям), ПКМ — осадка.
## Металл остывает; удар по холодному — трещина. «Нагреть» — если рядом горит горн или печь.
## «Готово» — балл формы идёт в качество части. Esc — бросить (слитки не тратятся).

signal finished(score: float)
signal cancelled()

var game: ForgeGame
var title := ""
## Callable() -> bool: есть ли жар рядом.
var can_heat: Callable
## Медленнее остывает (настройка доступности «Замедлить мини-игры»).
var slow := false

var _board: _Board
var _heat_btn: Button
var _info: Label


func _ready() -> void:
	layer = 26
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var t := Label.new()
	t.text = "Ковка: %s" % title
	t.add_theme_font_size_override("font_size", 22)
	box.add_child(t)
	var hint := Label.new()
	hint.text = "ЛКМ — вытяжка (столбик ниже, соседи выше), ПКМ — осадка. Подгоните форму под контур, пока металл горячий."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 560
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(hint)
	_board = _Board.new()
	_board.game = game
	_board.custom_minimum_size = Vector2(560, 300)
	_board.struck.connect(func() -> void:
		var audio := get_node_or_null(^"/root/Audio")
		if audio != null:
			audio.play_ui("crafting/anvil_hit"))
	box.add_child(_board)
	_info = Label.new()
	box.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_heat_btn = Button.new()
	_heat_btn.text = "Нагреть в горне"
	_heat_btn.pressed.connect(func() -> void: game.reheat())
	row.add_child(_heat_btn)
	var done := Button.new()
	done.text = "Готово"
	done.pressed.connect(func() -> void:
		finished.emit(game.finish())
		queue_free())
	row.add_child(done)
	var cancel := Button.new()
	cancel.text = "Бросить"
	cancel.pressed.connect(_cancel)
	row.add_child(cancel)
	box.add_child(row)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cancel() -> void:
	cancelled.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_cancel()


func _process(delta: float) -> void:
	game.cool(delta * (0.5 if slow else 1.0))
	_heat_btn.disabled = not can_heat.is_valid() or not can_heat.call()
	_info.text = "Жар: %d %% · удары: %d · трещины: %d · совпадение: %d %%" % [roundi(game.heat * 100.0), game.strikes,
		game.cracks, roundi(game.score() * 100.0)]
	_board.queue_redraw()


class _Board:
	extends Control
	signal struck()
	var game: ForgeGame

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var i := clampi(int(event.position.x / (size.x / ForgeGame.COLUMNS)), 0, ForgeGame.COLUMNS - 1)
			if event.button_index == MOUSE_BUTTON_LEFT:
				game.strike(i, true)
				struck.emit()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				game.strike(i, false)
				struck.emit()
			accept_event()

	func _draw() -> void:
		var w := size.x / ForgeGame.COLUMNS
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.09, 0.08))
		# Цвет металла по жару: вишнёвый → жёлтый.
		var hot := Color(0.35, 0.33, 0.32).lerp(Color(1.0, 0.55, 0.15), game.heat).lerp(Color(1, 0.9, 0.6), maxf(0.0, game.heat - 0.7))
		for i in ForgeGame.COLUMNS:
			var hgt := size.y * game.shape[i] / 10.0
			draw_rect(Rect2(i * w + 4, size.y - hgt, w - 8, hgt), hot)
			var th := size.y * game.target[i] / 10.0
			draw_rect(Rect2(i * w + 2, size.y - th, w - 4, th), Color(0.4, 0.9, 0.5, 0.9), false, 2.0)
		if game.heat < ForgeGame.COLD:
			draw_string(get_theme_default_font(), Vector2(10, 24), "Остыло — нагрейте!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				Color(0.6, 0.8, 1.0))
