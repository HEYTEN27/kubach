class_name UiTheme
extends RefCounted
## Тема интерфейса «Кубача»: тёмные полупрозрачные панели с тёплой деревянной окантовкой,
## ячейки инвентаря, кнопки. Учитывает настройки «Размер шрифта» и «Высокий контраст».

const BG := Color(0.09, 0.1, 0.095, 0.94)
const PANEL := Color(0.13, 0.14, 0.135, 0.96)
const BORDER := Color(0.48, 0.37, 0.24)
const ACCENT := Color(0.86, 0.68, 0.32)
const TEXT := Color(0.92, 0.9, 0.84)
const TEXT_DIM := Color(0.66, 0.66, 0.6)
const SLOT := Color(0.17, 0.18, 0.175, 0.95)
const SLOT_BORDER := Color(0.32, 0.31, 0.27)
const DANGER := Color(0.85, 0.35, 0.3)

## Цвета с учётом высокого контраста.
static var high_contrast := false


static func slot_color() -> Color:
	return Color(0, 0, 0, 1) if high_contrast else SLOT


static func slot_border() -> Color:
	return Color(1, 1, 1) if high_contrast else SLOT_BORDER


static func accent() -> Color:
	return Color(1, 0.95, 0.1) if high_contrast else ACCENT


static func box(bg: Color, border: Color, width: int = 2, radius: int = 6, margin: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func build(font_scale: float = 1.0, contrast: bool = false) -> Theme:
	high_contrast = contrast
	var t := Theme.new()
	var bg := Color(0, 0, 0, 0.97) if contrast else BG
	var border := Color(1, 1, 1) if contrast else BORDER
	var text := Color(1, 1, 1) if contrast else TEXT
	t.default_font_size = roundi(17 * font_scale)
	t.set_color("font_color", "Label", text)
	t.set_color("font_color", "Button", text)
	t.set_color("font_color", "CheckBox", text)
	t.set_color("font_color", "CheckButton", text)
	t.set_color("font_color", "OptionButton", text)
	t.set_color("font_color", "LineEdit", text)
	t.set_color("font_color", "ItemList", text)
	t.set_color("font_color", "TabBar", text.darkened(0.25))
	t.set_color("font_selected_color", "TabBar", accent())
	t.set_color("font_hover_color", "Button", accent())
	t.set_stylebox("panel", "Panel", box(bg, border))
	t.set_stylebox("panel", "PanelContainer", box(bg, border, 2, 8, 12))
	var btn := box(Color(0.2, 0.19, 0.16) if not contrast else Color(0, 0, 0), border, 2, 5, 8)
	var btn_hover := box(Color(0.28, 0.25, 0.19) if not contrast else Color(0.2, 0.2, 0), accent(), 2, 5, 8)
	var btn_pressed := box(Color(0.35, 0.29, 0.2), accent(), 2, 5, 8)
	var btn_disabled := box(Color(0.14, 0.14, 0.13), Color(0.25, 0.25, 0.23), 2, 5, 8)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_hover)
		t.set_stylebox("pressed", cls, btn_pressed)
		t.set_stylebox("focus", cls, box(Color(0, 0, 0, 0), accent(), 2, 5, 8))
		t.set_stylebox("disabled", cls, btn_disabled)
	t.set_stylebox("normal", "LineEdit", box(Color(0.07, 0.07, 0.07), border, 2, 4, 6))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), accent(), 2, 4, 6))
	t.set_stylebox("panel", "ItemList", box(Color(0.07, 0.08, 0.075, 0.9), border, 2, 4, 6))
	t.set_stylebox("panel", "TabContainer", box(bg, border, 2, 6, 10))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.24, 0.21, 0.16), accent(), 2, 4, 8))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.12, 0.12, 0.11), border, 1, 4, 8))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.2, 0.18, 0.14), accent(), 1, 4, 8))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.05, 0.05, 0.96), accent(), 2, 4, 8))
	t.set_color("font_color", "TooltipLabel", text)
	return t
