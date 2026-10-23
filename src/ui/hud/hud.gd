class_name Hud
extends CanvasLayer
## Игровой HUD этапа 1: прицел, прогресс ломания, выбранный блок, режим, предупреждение о краю
## мира, экран загрузки. Полный HUD (здоровье, голод, хотбар) — этапы 4–5.

const BORDER_WARNING_DISTANCE := 48.0

var player: Player
var world: World

var _crosshair: Control
var _break_bar: ProgressBar
var _selected: Label
var _mode: Label
var _border: Label
var _loading: Control
var _loading_label: Label
var _toast: Label
var _toast_time := 0.0


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_crosshair = _Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	_break_bar = ProgressBar.new()
	_break_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_break_bar.custom_minimum_size = Vector2(80, 6)
	_break_bar.position += Vector2(-40, 18)
	_break_bar.show_percentage = false
	_break_bar.max_value = 1.0
	_break_bar.visible = false
	root.add_child(_break_bar)

	_selected = _label(root, Control.PRESET_CENTER_BOTTOM, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_selected.position.y -= 48
	_mode = _label(root, Control.PRESET_BOTTOM_RIGHT, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	_mode.position += Vector2(-16, -36)
	_border = _label(root, Control.PRESET_CENTER_TOP, 22, HORIZONTAL_ALIGNMENT_CENTER)
	_border.position.y += 48
	_border.modulate = Color(1.0, 0.75, 0.45)
	_toast = _label(root, Control.PRESET_CENTER_TOP, 18, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.position.y += 96

	_loading = ColorRect.new()
	(_loading as ColorRect).color = Color(0.07, 0.09, 0.08, 1.0)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_loading)
	_loading_label = _label(_loading, Control.PRESET_CENTER, 28, HORIZONTAL_ALIGNMENT_CENTER)


func show_toast(text: String, seconds: float = 2.5) -> void:
	_toast.text = text
	_toast_time = seconds


func set_loading(visible_: bool, text: String = "") -> void:
	_loading.visible = visible_
	_loading_label.text = text


func _process(delta: float) -> void:
	if player == null or world == null:
		return
	var inter := player.interaction
	_break_bar.visible = inter.break_progress > 0.0
	_break_bar.value = inter.break_progress
	var def := world.registry.block_by_num(inter.selected_block())
	_selected.text = "%s   [%d/%d]" % [def.display_name() if def else "—", inter.selected + 1, inter.palette.size()]
	var mode := "Творческий" if world.game_mode == &"creative" else "Выживание"
	if player.motor.flying:
		mode += " · полёт"
	_mode.text = mode
	_crosshair.visible = player.camera_mode != Player.CameraMode.THIRD_FRONT

	var edge := float(WorldConst.WORLD_HALF) - maxf(absf(player.body.x), absf(player.body.z))
	_border.visible = edge < BORDER_WARNING_DISTANCE
	_border.text = "Край мира: до границы %d бл. Дальше пути нет." % maxi(0, floori(edge))

	_toast_time -= delta
	_toast.visible = _toast_time > 0.0


func _label(parent: Control, preset: Control.LayoutPreset, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN if align == HORIZONTAL_ALIGNMENT_RIGHT else Control.GROW_DIRECTION_BOTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


class _Crosshair:
	extends Control

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.85)
		var o := Color(0, 0, 0, 0.6)
		draw_line(Vector2(-9, 0), Vector2(9, 0), o, 4.0)
		draw_line(Vector2(0, -9), Vector2(0, 9), o, 4.0)
		draw_line(Vector2(-8, 0), Vector2(8, 0), c, 2.0)
		draw_line(Vector2(0, -8), Vector2(0, 8), c, 2.0)
