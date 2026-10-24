class_name Hud
extends CanvasLayer
## Игровой HUD: прицел (вид и размер — из настроек), прогресс ломания, хотбар с иконками,
## название предмета в руке, компас, FPS, режим, предупреждение о краю мира, экран загрузки.
## Здоровье, голод и прочие параметры выживания — этап 5.

const BORDER_WARNING_DISTANCE := 48.0

var player: Player
var world: World

var _crosshair: Control
var _break_bar: ProgressBar
var _selected: Label
var _hotbar: Control
var _compass: Label
var _fps: Label
var _root: Control
var _last_held: StringName = &"-"
var _name_time := 0.0
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
	_root = root

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

	_hotbar = _Hotbar.new()
	_hotbar.set("hud", self)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.custom_minimum_size = Vector2(9 * 56 + 8, 62)
	_hotbar.size = _hotbar.custom_minimum_size
	_hotbar.position = Vector2(-_hotbar.size.x * 0.5, -_hotbar.size.y - 10)
	root.add_child(_hotbar)
	_selected = _label(root, Control.PRESET_CENTER_BOTTOM, 19, HORIZONTAL_ALIGNMENT_CENTER)
	_selected.position.y -= 104
	_compass = _label(root, Control.PRESET_CENTER_TOP, 16, HORIZONTAL_ALIGNMENT_CENTER)
	_compass.position.y += 10
	_fps = _label(root, Control.PRESET_TOP_LEFT, 15, HORIZONTAL_ALIGNMENT_LEFT)
	_fps.position += Vector2(10, 8)
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
	var held := player.inventory.held()
	var held_id: StringName = held.id if held != null else &""
	if held_id != _last_held:
		_last_held = held_id
		_name_time = 2.5
	_name_time -= delta
	var d := world.registry.item(held_id) if held != null else null
	_selected.text = d.display_name() if d != null else ""
	_selected.visible = _name_time > 0.0 and bool(Settings.get_value("hud_item_name"))
	_selected.modulate.a = clampf(_name_time, 0.0, 1.0)
	_hotbar.visible = bool(Settings.get_value("hud_hotbar"))
	_hotbar.queue_redraw()
	_root.modulate.a = float(Settings.get_value("hud_opacity"))
	_compass.visible = bool(Settings.get_value("compass"))
	if _compass.visible:
		_compass.text = _compass_text(player.yaw)
	_fps.visible = bool(Settings.get_value("show_fps"))
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	(_crosshair as _Crosshair).style = String(Settings.get_value("crosshair_style"))
	(_crosshair as _Crosshair).scale_k = float(Settings.get_value("crosshair_size"))
	_crosshair.queue_redraw()
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


## Компас: стороны света по рысканию (−Z — север).
static func _compass_text(yaw: float) -> String:
	const NAMES := ["С", "СЗ", "З", "ЮЗ", "Ю", "ЮВ", "В", "СВ"]
	var deg := fposmod(rad_to_deg(yaw), 360.0)
	var i := roundi(deg / 45.0) % 8
	var left: String = NAMES[(i + 1) % 8]
	var right: String = NAMES[(i + 7) % 8]
	return "%s  ·  [ %s ]  ·  %s     %d°" % [left, NAMES[i], right, roundi(fposmod(360.0 - deg, 360.0))]


class _Crosshair:
	extends Control
	var style := "cross"
	var scale_k := 1.0

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.85)
		var o := Color(0, 0, 0, 0.6)
		var k := scale_k
		match style:
			"dot":
				draw_circle(Vector2.ZERO, 3.5 * k, o)
				draw_circle(Vector2.ZERO, 2.2 * k, c)
			"circle":
				draw_arc(Vector2.ZERO, 7.0 * k, 0, TAU, 32, o, 3.5)
				draw_arc(Vector2.ZERO, 7.0 * k, 0, TAU, 32, c, 1.8)
			_:
				draw_line(Vector2(-9, 0) * k, Vector2(9, 0) * k, o, 4.0)
				draw_line(Vector2(0, -9) * k, Vector2(0, 9) * k, o, 4.0)
				draw_line(Vector2(-8, 0) * k, Vector2(8, 0) * k, c, 2.0)
				draw_line(Vector2(0, -8) * k, Vector2(0, 8) * k, c, 2.0)


class _Hotbar:
	extends Control
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.player == null:
			return
		var inv := hud.player.inventory
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		for i in PlayerInventory.HOTBAR:
			var r := Rect2(Vector2(4 + i * 56, 5), Vector2(52, 52))
			draw_rect(r, Color(0.12, 0.12, 0.12, 0.7))
			var sel := i == inv.selected
			draw_rect(r.grow(-1), UiTheme.accent() if sel else Color(0.4, 0.4, 0.38, 0.8), false, 3.0 if sel else 1.5)
			var s := inv.hotbar.get_stack(i)
			if s != null:
				ItemSlot.draw_item(self, s, r.grow(-6))
			var font := ThemeDB.fallback_font
			draw_string(font, r.position + Vector2(4, 13), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
