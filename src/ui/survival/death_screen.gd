class_name DeathScreen
extends CanvasLayer
## Экран смерти: причина, сколько прожито, «Возродиться» (у кровати или в точке мира) или
## «В главное меню». В хардкоре возрождения нет — мир остаётся только для осмотра.

signal respawn_requested()
signal menu_requested()

const CAUSES := {
	"starve": "Умер от голода", "thirst": "Умер от жажды", "cold": "Замёрз насмерть",
	"heat": "Тепловой удар", "drown": "Утонул", "fall": "Разбился при падении",
	"fire": "Сгорел", "contact": "Изранен", "hail": "Забит градом", "lightning": "Убит молнией",
}

var cause := ""
var days := 0
var one_life := false
var drop_note := ""
var registry: ContentRegistry


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.25, 0.0, 0.0, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.6, 1.2)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 420
	center.add_child(box)
	var title := Label.new()
	title.text = "Вы погибли"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	box.add_child(title)
	var info := Label.new()
	info.text = "%s\nПрожито дней: %d%s" % [cause_text(cause, registry), days, ("\n" + drop_note) if drop_note != "" else ""]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 20)
	box.add_child(info)
	if one_life:
		var hc := Label.new()
		hc.text = "Хардкор: у этого мира была одна жизнь.\nОн останется доступен только для осмотра."
		hc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hc)
	else:
		var b := Button.new()
		b.text = "Возродиться"
		b.custom_minimum_size = Vector2(420, 48)
		b.pressed.connect(_on_respawn)
		box.add_child(b)
		b.grab_focus.call_deferred()
	var m := Button.new()
	m.text = "В главное меню"
	m.custom_minimum_size = Vector2(420, 44)
	m.pressed.connect(_on_menu)
	box.add_child(m)


func _on_respawn() -> void:
	respawn_requested.emit()
	queue_free()


func _on_menu() -> void:
	menu_requested.emit()


static func cause_text(c: String, registry: ContentRegistry = null) -> String:
	if CAUSES.has(c):
		return CAUSES[c]
	if registry != null and registry.has_entry("effects", StringName(c)):
		return "Причина: %s" % registry.get_entry("effects", StringName(c))["name"]["ru"]
	return "Причина неизвестна"
