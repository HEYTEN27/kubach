class_name RecipeBookPanel
extends PanelContainer
## Книга рецептов (раздел 5.5 ТЗ): известные рецепты по станциям с входами, временем, жаром и
## мини-игрой. Неизвестные не показываются — только их число. Открываются, когда впервые
## видишь все ингредиенты, или чертежом.

var controller: CraftingController

var _station: OptionButton
var _search: LineEdit
var _text: RichTextLabel
var _count: Label
var _ids: Array[StringName] = []


func _ready() -> void:
	custom_minimum_size = Vector2(440, 480)
	var box := VBoxContainer.new()
	add_child(box)
	_count = Label.new()
	box.add_child(_count)
	var head := HBoxContainer.new()
	_station = OptionButton.new()
	var st: Array = controller.data.stations.values()
	st.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	for s: Dictionary in st:
		_station.add_item(String(s["name"]["ru"]))
		_ids.append(StringName(s["id"]))
	_station.item_selected.connect(func(_i: int) -> void: _fill())
	head.add_child(_station)
	_search = LineEdit.new()
	_search.placeholder_text = "Поиск…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	head.add_child(_search)
	box.add_child(head)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.scroll_active = true
	box.add_child(_text)
	_fill()


func _fill() -> void:
	var data := controller.data
	var book := controller.book
	var c := book.counts()
	_count.text = "Известно рецептов: %d из %d" % [c.x, c.y]
	var sid := _ids[_station.selected]
	var q := _search.text.strip_edges().to_lower()
	var lines := PackedStringArray()
	var hidden := 0
	var cat := ""
	for r: Dictionary in data.recipes_for(sid):
		if not book.is_known(StringName(r["id"])):
			hidden += 1
			continue
		var name := data.recipe_name(r)
		if q != "" and not name.to_lower().contains(q):
			continue
		if String(r["category"]) != cat:
			cat = String(r["category"])
			lines.append("\n[b]%s[/b]" % CATEGORY_NAMES.get(cat, cat))
		var extra := PackedStringArray()
		if float(r.get("time", 0.0)) > 0.0:
			extra.append(time_text(float(r["time"])))
		if float(r.get("heat", 0.0)) > 0.0:
			extra.append("%d °C" % roundi(float(r["heat"])))
		var mg := String(r.get("minigame", "none"))
		if mg != "none":
			extra.append({ "forge": "ковка", "smelt": "плавка", "cook": "готовка" }.get(mg, mg))
		if int(r.get("min_tier", 0)) > 0:
			extra.append("уровень станции %d" % int(r["min_tier"]))
		var n := int(r.get("output", {}).get("count", 1))
		lines.append("• %s%s — %s%s" % [name, " ×%d" % n if n > 1 else "", HandCraftPanel.inputs_line(data, r),
			("  [color=#a0a0a0](%s)[/color]" % ", ".join(extra)) if not extra.is_empty() else ""])
	if hidden > 0:
		lines.append("\n[color=#a0a0a0]Ещё не открыто: %d — найдите ингредиенты или чертежи.[/color]" % hidden)
	_text.text = "\n".join(lines)


## Игровые минуты → «12 мин», «2 ч», «2 сут».
static func time_text(minutes: float) -> String:
	if minutes >= 1440.0:
		return "%s сут" % str(snappedf(minutes / 1440.0, 0.1))
	if minutes >= 60.0:
		return "%s ч" % str(snappedf(minutes / 60.0, 0.1))
	return "%d мин" % roundi(minutes)


const CATEGORY_NAMES := {
	"basic": "Основное", "parts": "Части", "tools": "Инструменты", "stations": "Станции", "medicine": "Лечение",
	"pottery": "Гончарное дело", "blocks": "Блоки", "planks": "Доски", "kitchen": "Посуда", "leather": "Кожа",
	"textile": "Ткань", "storage": "Хранение", "furniture": "Мебель", "weapons": "Оружие", "clothing": "Одежда",
	"fuel": "Топливо", "ore": "Руда", "ingots": "Слитки", "misc": "Разное", "dyes": "Краски", "food": "Еда",
	"service": "Обслуживание",
}
