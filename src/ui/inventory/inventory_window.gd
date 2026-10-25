class_name InventoryWindow
extends CanvasLayer
## Окно инвентаря (раздел 4.4 ТЗ): экипировка и вращаемая 3D-модель персонажа слева,
## рюкзак, основной инвентарь и хотбар справа, сверху — открытый сундук (с поиском и
## «сложить похожее»), в творческом режиме — каталог всех предметов с вкладками, поиском
## и корзиной. Все операции идут через слой действий: execute(InventoryAction).
##
## Мышь: ЛКМ — взять/положить/поменять, ПКМ — половина/по одной, протяжка ПКМ — по одной в
## каждую ячейку, Shift+ЛКМ — быстрый перенос, двойной клик — собрать такие же, клик вне окна —
## выбросить (ЛКМ — всё, ПКМ — одну). Клавиши над ячейкой: 1…9 — обмен с хотбаром,
## Q — выбросить (Ctrl+Q — стопку). E или Esc — закрыть.

signal closed()

const EQUIP_LABELS := ["Голова", "Тело", "Ноги", "Ступни", "Руки", "Спина", "Аксес.", "Аксес.", "2-я рука"]
const CATALOG_TABS := [
	["Все", []], ["Строительство", [&"block"]], ["Инструменты", [&"tool", &"weapon"]],
	["Одежда", [&"armor", &"clothing", &"backpack", &"accessory", &"shield"]], ["Еда", [&"food"]],
	["Материалы", [&"material", &"misc", &"light", &"part"]],
]

var ops: InventoryOps
var player_inv: PlayerInventory
var registry: ContentRegistry
## Выполнить действие (Game.execute_inventory) — Callable(InventoryAction) -> bool.
var executor: Callable
var creative := false
var container_title := ""
var appearance := {}
## Ремесло (этап 6): контроллер (вкладки «Ремесло» и «Книга рецептов») и панель станции,
## которая встаёт над инвентарём вместо сетки сундука.
var crafting: CraftingController
var station_panel: Control

var _root: Control
var _slots: Array[ItemSlot] = []
var _cursor: Control
var _tooltip: PanelContainer
var _tooltip_label: Label
var _hover: ItemSlot
var _weight: Label
var _search: LineEdit
var _catalog_grid: GridContainer
var _catalog_tab := 0
var _preview: CharacterPreview
var _backpack_box: Control
var _backpack_grid: GridContainer
var _last_click := {}
var _rdrag := false


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_outside_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	center.add_child(row)

	if creative:
		row.add_child(_build_catalog())
	row.add_child(_build_left())
	row.add_child(_build_storage())

	_cursor = _CursorItem.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.set("window", self)
	_root.add_child(_cursor)
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("panel", UiTheme.box(Color(0.05, 0.05, 0.05, 0.96), UiTheme.accent(), 2, 4, 8))
	_tooltip_label = Label.new()
	_tooltip.add_child(_tooltip_label)
	_tooltip.visible = false
	_root.add_child(_tooltip)

	for inv: Inventory in [player_inv.hotbar, player_inv.main, player_inv.backpack, player_inv.equipment]:
		inv.changed.connect(_refresh)
	if ops.container != null:
		ops.container.changed.connect(_refresh)
	for inv: Inventory in ops.station.values():
		inv.changed.connect(_refresh)
	player_inv.equipment_changed.connect(_rebuild_backpack)
	_refresh()


## Левая колонка: вкладки «Персонаж», «Ремесло» (ручные рецепты), «Книга рецептов».
func _build_left() -> Control:
	var ch := _build_character()
	if crafting == null:
		return ch
	var box := VBoxContainer.new()
	var tabs := TabBar.new()
	tabs.add_tab("Персонаж")
	tabs.add_tab("Ремесло")
	tabs.add_tab("Книга рецептов")
	box.add_child(tabs)
	var hand := HandCraftPanel.new()
	hand.controller = crafting
	hand.window = self
	var bookp := RecipeBookPanel.new()
	bookp.controller = crafting
	var pages: Array[Control] = [ch, hand, bookp]
	for pg in pages:
		pg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(pg)
		pg.visible = pg == ch
	tabs.tab_changed.connect(func(i: int) -> void:
		for k in pages.size():
			pages[k].visible = k == i)
	if station_panel == null and _remembered_tab > 0:
		tabs.current_tab = _remembered_tab
	tabs.tab_changed.connect(func(i: int) -> void: InventoryWindow._remembered_tab = i)
	return box


static var _remembered_tab := 0


func _build_character() -> Control:
	var panel := PanelContainer.new()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var eq := VBoxContainer.new()
	eq.add_theme_constant_override("separation", 4)
	box.add_child(eq)
	var title := Label.new()
	title.text = "Экипировка"
	eq.add_child(title)
	for i in player_inv.equipment.size():
		var s := _slot(player_inv.equipment, i)
		s.placeholder = EQUIP_LABELS[i]
		eq.add_child(s)
	var right := VBoxContainer.new()
	box.add_child(right)
	_preview = CharacterPreview.new(Vector2i(240, 400))
	_preview.setup(registry, appearance, player_inv.equipment)
	right.add_child(_preview)
	var hint := Label.new()
	hint.text = "Потяните, чтобы повернуть"
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(hint)
	_weight = Label.new()
	right.add_child(_weight)
	return panel


func _build_storage() -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	if station_panel != null:
		box.add_child(station_panel)
		box.add_child(HSeparator.new())
	elif ops.container != null:
		var head := HBoxContainer.new()
		var t := Label.new()
		t.text = container_title
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		_search = LineEdit.new()
		_search.placeholder_text = "Поиск…"
		_search.custom_minimum_size.x = 160
		_search.text_changed.connect(func(_t: String) -> void: _refresh())
		head.add_child(_search)
		var dep := Button.new()
		dep.text = "Сложить похожее"
		dep.tooltip_text = "Переложить в сундук всё, что в нём уже есть"
		dep.pressed.connect(func() -> void: _do(InventoryAction.make(InventoryAction.Op.DEPOSIT_SIMILAR)))
		head.add_child(dep)
		var sort_c := Button.new()
		sort_c.text = "Сортировать"
		sort_c.pressed.connect(func() -> void: _do(InventoryAction.make(InventoryAction.Op.SORT, "container")))
		head.add_child(sort_c)
		box.add_child(head)
		box.add_child(_grid(ops.container, 9))
		box.add_child(HSeparator.new())
	_backpack_box = VBoxContainer.new()
	box.add_child(_backpack_box)
	_rebuild_backpack()
	var head2 := HBoxContainer.new()
	var t2 := Label.new()
	t2.text = "Инвентарь"
	t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head2.add_child(t2)
	var sort := Button.new()
	sort.text = "Сортировать"
	sort.pressed.connect(func() -> void: _do(InventoryAction.make(InventoryAction.Op.SORT, "main")))
	head2.add_child(sort)
	if creative:
		var trash := Button.new()
		trash.text = "🗑 Корзина"
		trash.tooltip_text = "Положите сюда предмет с курсора, чтобы удалить"
		trash.pressed.connect(func() -> void: _do(InventoryAction.make(InventoryAction.Op.TRASH)))
		head2.add_child(trash)
	box.add_child(head2)
	box.add_child(_grid(player_inv.main, 9))
	var hb := Label.new()
	hb.text = "Хотбар"
	box.add_child(hb)
	box.add_child(_grid(player_inv.hotbar, 9))
	return panel


func _rebuild_backpack() -> void:
	if _backpack_box == null:
		return
	for c in _backpack_box.get_children():
		if c == _backpack_grid:
			for s in c.get_children():
				_slots.erase(s)
		c.queue_free()
	_backpack_grid = null
	if player_inv.backpack.size() == 0:
		return
	var t := Label.new()
	t.text = "Рюкзак (+%d)" % player_inv.backpack.size()
	_backpack_box.add_child(t)
	_backpack_grid = _grid(player_inv.backpack, 9)
	_backpack_box.add_child(_backpack_grid)
	_refresh()


func _build_catalog() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var t := Label.new()
	t.text = "Каталог (творческий режим)"
	box.add_child(t)
	var tabs := HBoxContainer.new()
	for i in CATALOG_TABS.size():
		var b := Button.new()
		b.text = CATALOG_TABS[i][0]
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.pressed.connect(func() -> void:
			_catalog_tab = i
			for k in tabs.get_child_count():
				(tabs.get_child(k) as Button).button_pressed = k == i
			_fill_catalog())
		b.add_theme_font_size_override("font_size", 13)
		tabs.add_child(b)
	box.add_child(tabs)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск предмета…"
	search.text_changed.connect(func(_t: String) -> void: _fill_catalog())
	search.name = "CatalogSearch"
	box.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_catalog_grid = GridContainer.new()
	_catalog_grid.columns = 8
	scroll.add_child(_catalog_grid)
	var hint := Label.new()
	hint.text = "ЛКМ — стопка, ПКМ — одна штука, Shift — сразу в инвентарь"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(hint)
	_fill_catalog.call_deferred()
	return panel


func _fill_catalog() -> void:
	for c in _catalog_grid.get_children():
		c.queue_free()
	var search := (_catalog_grid.get_parent().get_parent().get_node("CatalogSearch") as LineEdit).text.strip_edges().to_lower()
	var kinds: Array = CATALOG_TABS[_catalog_tab][1]
	for d in registry.items():
		if not kinds.is_empty() and not kinds.has(d.kind):
			continue
		if search != "" and not d.display_name().to_lower().contains(search) and not String(d.id).contains(search):
			continue
		var s := ItemSlot.new()
		s.catalog_item = d.id
		s.owner_window = self
		s.custom_minimum_size = Vector2(54, 54)
		_catalog_grid.add_child(s)


func _grid(inv: Inventory, columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	for i in inv.size():
		g.add_child(_slot(inv, i))
	return g


## Ячейка окна для чужого инвентаря (панель станции).
func make_slot(inv: Inventory, i: int, placeholder: String = "") -> ItemSlot:
	var s := _slot(inv, i)
	s.placeholder = placeholder
	return s


func _slot(inv: Inventory, i: int) -> ItemSlot:
	var s := ItemSlot.new()
	s.inv = inv
	s.index = i
	s.owner_window = self
	_slots.append(s)
	return s


func _name_of(inv: Inventory) -> String:
	if inv == player_inv.hotbar:
		return "hotbar"
	if inv == player_inv.main:
		return "main"
	if inv == player_inv.backpack:
		return "backpack"
	if inv == player_inv.equipment:
		return "equipment"
	for k: String in ops.station:
		if ops.station[k] == inv:
			return k
	return "container"


func _do(a: InventoryAction) -> void:
	executor.call(a)
	_refresh()


func slot_input(slot: ItemSlot, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if slot.catalog_item != &"":
			_catalog_click(slot, event)
			return
		var name := _name_of(slot.inv)
		if event.button_index == MOUSE_BUTTON_LEFT:
			var now := Time.get_ticks_msec()
			var dbl: bool = _last_click.get("slot") == slot and now - int(_last_click.get("t", 0)) < 320
			_last_click = { "slot": slot, "t": now }
			var op := InventoryAction.Op.LEFT
			if event.shift_pressed:
				op = InventoryAction.Op.SHIFT
			elif dbl or event.double_click:
				op = InventoryAction.Op.DOUBLE
			_do(InventoryAction.make(op, name, slot.index))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_rdrag = ops.cursor != null
			_do(InventoryAction.make(InventoryAction.Op.RIGHT, name, slot.index))
			if _rdrag:
				ops.right_drag(slot.inv, slot.index)
		slot.accept_event()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_rdrag = false
		ops.end_drag()


func _catalog_click(slot: ItemSlot, event: InputEventMouseButton) -> void:
	var a := InventoryAction.make(InventoryAction.Op.TAKE_CREATIVE)
	a.item_id = slot.catalog_item
	a.amount = 1 if event.button_index == MOUSE_BUTTON_RIGHT else 0
	if ops.cursor != null and ops.cursor.id != slot.catalog_item and event.button_index == MOUSE_BUTTON_LEFT:
		# Клик по каталогу с чужим предметом на курсоре — удалить его (как корзина).
		_do(InventoryAction.make(InventoryAction.Op.TRASH))
		return
	_do(a)
	if event.shift_pressed and ops.cursor != null:
		player_inv.add(ops.cursor)
		if ops.cursor.count == 0:
			ops.cursor = null
		_refresh()
	slot.accept_event()


func slot_hover(slot: ItemSlot, inside: bool) -> void:
	_hover = slot if inside else (null if _hover == slot else _hover)
	if inside and _rdrag and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and slot.inv != null:
		var a := InventoryAction.make(InventoryAction.Op.RIGHT_DRAG, _name_of(slot.inv), slot.index)
		_do(a)
	_update_tooltip()


func _outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and ops.cursor != null:
		var a := InventoryAction.make(InventoryAction.Op.DROP_CURSOR)
		a.amount = 1 if event.button_index == MOUSE_BUTTON_RIGHT else 0
		_do(a)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and _hover != null and _hover.inv != null:
		var name := _name_of(_hover.inv)
		if event.is_action(&"drop_item"):
			var a := InventoryAction.make(InventoryAction.Op.DROP_SLOT, name, _hover.index)
			a.amount = 0 if event.ctrl_pressed else 1
			_do(a)
			get_viewport().set_input_as_handled()
			return
		for i in 9:
			if event.is_action(StringName("hotbar_%d" % (i + 1))):
				var a := InventoryAction.make(InventoryAction.Op.HOTBAR_SWAP, name, _hover.index)
				a.amount = i
				_do(a)
				get_viewport().set_input_as_handled()
				return


func close() -> void:
	ops.close()
	closed.emit()
	queue_free()


## Перерисовать (панели ремесла зовут после действий).
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	for s in _slots:
		if not is_instance_valid(s):
			continue
		s.selected = s.inv == player_inv.hotbar and s.index == player_inv.selected
		s.dimmed = false
		if q != "" and s.inv == ops.container:
			var st := s.stack()
			var d := registry.item(st.id) if st != null else null
			s.dimmed = d == null or not d.display_name().to_lower().contains(q)
		s.queue_redraw()
	if _weight != null:
		var w := player_inv.total_weight()
		var use_weight := bool(Settings.get_value("weight")) and not creative
		_weight.text = ("Вес: %.1f / %.0f кг" % [w, PlayerInventory.CARRY_LIMIT]) if use_weight else ("Вес: %.1f кг" % w)
		_weight.add_theme_color_override("font_color",
			UiTheme.DANGER if use_weight and w > PlayerInventory.CARRY_LIMIT else UiTheme.TEXT_DIM)
	if _cursor != null:
		_cursor.queue_redraw()
	_update_tooltip()


func _update_tooltip() -> void:
	var s := _hover.stack() if _hover != null and is_instance_valid(_hover) else null
	if s == null or ops.cursor != null:
		_tooltip.visible = false
		return
	var lines := ItemTooltip.lines(s, registry)
	if _hover.catalog_item != &"":
		lines = lines.slice(0, 2)
	_tooltip_label.text = "\n".join(lines)
	_tooltip.visible = true
	_tooltip.reset_size()


func _process(_delta: float) -> void:
	var m := _root.get_local_mouse_position()
	if _tooltip.visible:
		var p := m + Vector2(18, 18)
		var vs := _root.size
		p.x = minf(p.x, vs.x - _tooltip.size.x - 4)
		p.y = minf(p.y, vs.y - _tooltip.size.y - 4)
		_tooltip.position = p
	_cursor.position = m - Vector2(26, 26)
	_cursor.queue_redraw()


class _CursorItem:
	extends Control
	var window: InventoryWindow

	func _init() -> void:
		size = Vector2(52, 52)

	func _draw() -> void:
		if window == null or window.ops.cursor == null:
			return
		ItemSlot.draw_item(self, window.ops.cursor, Rect2(Vector2(4, 4), Vector2(44, 44)))
