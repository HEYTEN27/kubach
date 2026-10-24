class_name ItemSlot
extends Control
## Ячейка инвентаря: фон, иконка, количество, полоска прочности, подпись пустого слота
## экипировки. Ввод мыши передаётся окну (owner_window.slot_input).

const SIZE := 52.0

var inv: Inventory
var index := 0
var placeholder := ""
var selected := false
## Затемнить (поиск по сундуку не нашёл).
var dimmed := false
## Для творческого каталога: предмет без инвентаря.
var catalog_item: StringName = &""
var owner_window: Object


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func stack() -> ItemStack:
	if catalog_item != &"":
		return ItemStack.make(catalog_item, 1)
	return inv.get_stack(index) if inv != null else null


func _gui_input(event: InputEvent) -> void:
	if owner_window != null:
		owner_window.slot_input(self, event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER and owner_window != null:
		owner_window.slot_hover(self, true)
	elif what == NOTIFICATION_MOUSE_EXIT and owner_window != null:
		owner_window.slot_hover(self, false)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, UiTheme.slot_color())
	var border := UiTheme.accent() if selected else UiTheme.slot_border()
	draw_rect(r.grow(-1), border, false, 3.0 if selected else 2.0)
	var s := stack()
	if s == null:
		if placeholder != "":
			var font := get_theme_default_font()
			var fs := 11
			var w := font.get_string_size(placeholder, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.58), placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1, 1, 1, 0.35))
		return
	draw_item(self, s, r.grow(-5), dimmed)


## Нарисовать стопку в прямоугольнике (ячейки, курсор, хотбар HUD).
static func draw_item(c: CanvasItem, s: ItemStack, r: Rect2, dim: bool = false) -> void:
	var tex := ItemIcons.shared().icon(s.id)
	c.draw_texture_rect(tex, r, false, Color(1, 1, 1, 0.3) if dim else Color.WHITE)
	var reg := ItemIcons.registry()
	var d := reg.item(s.id) if reg else null
	if d != null and d.durability > 0 and s.data.has("durability"):
		var k := clampf(float(s.data["durability"]) / d.durability, 0.0, 1.0)
		if k < 1.0:
			var bar := Rect2(r.position.x + 2, r.end.y - 4, r.size.x - 4, 4)
			c.draw_rect(bar, Color(0, 0, 0, 0.8))
			c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(1.0 - k, 0.2 + 0.7 * k, 0.15))
	if s.count > 1:
		var font := ThemeDB.fallback_font
		var txt := str(s.count)
		var fs := 15
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs).x
		var p := Vector2(r.end.x - w + 3, r.end.y + 3)
		c.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		c.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
