class_name HandCraftPanel
extends PanelContainer
## Вкладка «Ремесло» в окне инвентаря (раздел 5.5 ТЗ): ручные рецепты — только простейшее
## (палки, бечёвка, верёвка, кремнёвые части и инструменты, верстак, костёр). Остальное
## делается на станциях. Показываются известные рецепты; «Только доступные» прячет то, на что
## не хватает материалов.

var controller: CraftingController
var window: InventoryWindow

var _list: VBoxContainer
var _only: CheckBox
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(440, 480)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "Руками"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_only = CheckBox.new()
	_only.text = "Только доступные"
	_only.toggled.connect(func(_on: bool) -> void: _dirty = true)
	head.add_child(_only)
	box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var hint := Label.new()
	hint.text = "Остальное — на станциях: верстак, печь, наковальня… (их рецепты — на верстаке)"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(hint)
	controller.player.inventory.changed.connect(_mark)


func _mark() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and is_visible_in_tree():
		_dirty = false
		_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var data := controller.data
	var inv := controller.player.inventory
	for r: Dictionary in controller.hand_recipes():
		var why := Crafting.hand_blocker(data, r, inv)
		if _only.button_pressed and why != "":
			continue
		_list.add_child(recipe_row(data, r, why, func() -> void:
			controller.craft_hand(r)
			_dirty = true
			if window != null:
				window.refresh()))


## Строка рецепта: иконка выхода, название, входы, кнопка (общая для панелей).
static func recipe_row(data: CraftingData, r: Dictionary, why: String, action: Callable, button := "Сделать") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var oid := String(r.get("output", {}).get("id", r.get("tool_type", "")))
	icon.texture = ItemIcons.shared().icon(StringName(oid))
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := Label.new()
	var n := int(r.get("output", {}).get("count", 1))
	name.text = data.recipe_name(r) + (" ×%d" % n if n > 1 else "")
	text.add_child(name)
	var ins := Label.new()
	ins.text = inputs_line(data, r)
	ins.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ins.add_theme_font_size_override("font_size", 12)
	ins.add_theme_color_override("font_color", UiTheme.DANGER if why != "" else UiTheme.TEXT_DIM)
	text.add_child(ins)
	row.add_child(text)
	var b := Button.new()
	b.text = button
	b.disabled = why != ""
	b.tooltip_text = why
	b.pressed.connect(action)
	row.add_child(b)
	return row


## Входы рецепта одной строкой.
static func inputs_line(data: CraftingData, r: Dictionary) -> String:
	match String(r.get("op", "craft")):
		"assemble":
			var t: Dictionary = data.tool_types.get(StringName(r["tool_type"]), {})
			var parts := PackedStringArray()
			for k: String in ["head", "handle", "binding"]:
				var d := data.registry.item(StringName(t.get(k, "")))
				parts.append(d.display_name().to_lower() if d != null else "?")
			var cats: Array = r.get("categories", [])
			return " + ".join(parts) + (" (навершие из камня или кремня)" if cats == ["stone"] else "")
		"alloy":
			for a in data.alloys:
				if String(a["id"]) == String(r.get("tool_type", "")):
					var comps := PackedStringArray()
					for c: Dictionary in a["components"]:
						comps.append("%s %d %%" % [data.material_name(StringName(c["material"])).to_lower() if data.materials.has(StringName(c["material"])) else "углерод", roundi(float(c["share"]) * 100.0)])
					return ", ".join(comps)
		"quench":
			return "металлическое навершие (+ топлёный жир — закалка в масле без трещин)"
		"sharpen":
			return "любое навершие или клинок"
		"dye":
			return "ткань + краска"
	var parts2 := PackedStringArray()
	for inp: Dictionary in r.get("inputs", []):
		parts2.append(data.input_text(inp))
	var line := ", ".join(parts2)
	if String(r.get("needs_tool", "none")) != "none":
		line += " · нужен инструмент: %s" % ItemTooltip.TOOLS.get(StringName(r["needs_tool"]), r["needs_tool"])
	return line
