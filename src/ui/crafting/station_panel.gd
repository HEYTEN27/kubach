class_name StationPanel
extends VBoxContainer
## Панель станции над инвентарём (раздел 5–6 ТЗ):
## - процесс (печь, дробилка, прялка…): входы → прогресс → выход, топливо, шкала жара с
##   зелёной зоной нужной температуры, мехи (удерживать) и заслонка — мини-игра плавки;
##   у костра — полоса прожарки с зонами и «Снять» (мини-игра готовки);
## - рецепты (верстак, столяр, наковальня…): список известных рецептов, что есть у игрока,
##   «Сделать» и «×5», очередь, выбор металла для ковки (наковальня — мини-игра ковки);
## - верстак: сборка из трёх частей с предпросмотром свойств, ремонт и разборка.
## В авто-режиме мини-игр печь держит жар сама, еда снимается сама.

var controller: CraftingController
var station: Station
var pos: Vector3i
var window: InventoryWindow

var _status: Label
var _progress: ProgressBar
var _gauge: _Gauge
var _cook: _CookBar
var _bellows: Button
var _damper: HSlider
var _recipes: VBoxContainer
var _queue: Label
var _preview: Label
var _metal: OptionButton
var _dirty := true
var _pump_t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	var block_name := controller.world.registry.block_by_num(controller.world.get_block(pos.x, pos.y, pos.z)).display_name()
	title.text = block_name
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	if station.is_process():
		_build_process()
	else:
		_build_recipe_mode()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 480
	add_child(_status)
	controller.player.inventory.changed.connect(_mark)


func _mark() -> void:
	_dirty = true


func _slots_row(label: String, inv: Inventory, placeholders: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if label != "":
		var l := Label.new()
		l.text = label
		l.custom_minimum_size.x = 74
		row.add_child(l)
	for i in inv.size():
		row.add_child(window.make_slot(inv, i, String(placeholders[i]) if i < placeholders.size() else ""))
	return row


func _build_process() -> void:
	var def := station.def
	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 10)
	flow.add_child(_slots_row("Вход", station.inputs))
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(90, 18)
	_progress.show_percentage = false
	_progress.max_value = 1.0
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(_progress)
	flow.add_child(_slots_row("", station.outputs))
	add_child(flow)
	if station.fuel.size() > 0:
		add_child(_slots_row("Топливо", station.fuel))
	if station.has_heat():
		_gauge = _Gauge.new()
		_gauge.station = station
		_gauge.custom_minimum_size = Vector2(480, 26)
		add_child(_gauge)
		if not station.auto:
			var ctl := HBoxContainer.new()
			ctl.add_theme_constant_override("separation", 10)
			if float(def.get("bellows", 0.0)) > 0.0:
				_bellows = Button.new()
				_bellows.text = "Мехи (держать)"
				_bellows.tooltip_text = "Качать мехи — жар выше, топливо горит быстрее"
				ctl.add_child(_bellows)
			var dl := Label.new()
			dl.text = "Заслонка"
			ctl.add_child(dl)
			_damper = HSlider.new()
			_damper.min_value = 0.0
			_damper.max_value = 1.0
			_damper.step = 0.01
			_damper.value = station.damper
			_damper.custom_minimum_size.x = 160
			_damper.tooltip_text = "Прикрыть — печь холоднее: держите стрелку в зелёной зоне"
			_damper.value_changed.connect(func(v: float) -> void: station.set_damper(v))
			ctl.add_child(_damper)
			add_child(ctl)
	var cooks := false
	for r: Dictionary in controller.data.recipes_for(station.kind):
		cooks = cooks or String(r.get("op", "")) == "cook"
	if cooks:
		_cook = _CookBar.new()
		_cook.station = station
		_cook.custom_minimum_size = Vector2(480, 22)
		add_child(_cook)
		if not station.auto:
			var take := Button.new()
			take.text = "Снять с огня"
			take.tooltip_text = "Снимите, когда полоса в зелёной зоне. Забудете — сгорит."
			take.pressed.connect(func() -> void:
				if station.take_cook():
					station.advance(0.0)
					controller.stations.flush(pos))
			add_child(take)


func _build_recipe_mode() -> void:
	var def := station.def
	if bool(def.get("assembly", false)) or bool(def.get("repair", false)):
		var asm := HBoxContainer.new()
		asm.add_theme_constant_override("separation", 8)
		var names := ["Навершие", "Рукоять", "Обмотка"] if bool(def.get("assembly", false)) else ["Инструмент"]
		asm.add_child(_slots_row("Части" if names.size() == 3 else "Ремонт", station.inputs, names))
		var btns := VBoxContainer.new()
		if bool(def.get("assembly", false)):
			btns.add_child(_button("Собрать", func() -> void: controller.assemble(station)))
		if bool(def.get("repair", false)):
			btns.add_child(_button("Починить", func() -> void: controller.repair(station),
				"Инструмент — в первую ячейку; материал навершия берётся из инвентаря"))
		if bool(def.get("salvage", false)):
			btns.add_child(_button("Разобрать", func() -> void: controller.salvage(station),
				"Инструмент — в первую ячейку: вернутся навершие и (если цел) рукоять"))
		asm.add_child(btns)
		add_child(asm)
		_preview = Label.new()
		_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preview.custom_minimum_size.x = 480
		_preview.add_theme_font_size_override("font_size", 13)
		_preview.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		add_child(_preview)
	if bool(def.get("forge", false)):
		var mrow := HBoxContainer.new()
		var ml := Label.new()
		ml.text = "Металл"
		mrow.add_child(ml)
		_metal = OptionButton.new()
		_metal.custom_minimum_size.x = 200
		mrow.add_child(_metal)
		add_child(mrow)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipes = VBoxContainer.new()
	_recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_recipes)
	add_child(scroll)
	var out := HBoxContainer.new()
	out.add_child(_slots_row("Готово", station.outputs))
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(120, 18)
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	out.add_child(_progress)
	_queue = Label.new()
	out.add_child(_queue)
	add_child(out)


func _button(text: String, action: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(func() -> void:
		action.call()
		_dirty = true
		window.refresh())
	return b


func _rebuild_recipes() -> void:
	if _recipes == null:
		return
	for c in _recipes.get_children():
		c.queue_free()
	var data := controller.data
	if _metal != null:
		var keep := _metal.get_item_text(_metal.selected) if _metal.selected >= 0 else ""
		_metal.clear()
		var seen := {}
		for r: Dictionary in controller.station_recipes(station):
			if String(r.get("op", "")) == "forge_part":
				for m: Array in controller.forge_materials(r):
					if not seen.has(m[0]):
						seen[m[0]] = true
						_metal.add_item("%s (%d)" % [data.material_name(m[0]), int(m[1])])
						_metal.set_item_metadata(_metal.item_count - 1, String(m[0]))
		for i in _metal.item_count:
			if _metal.get_item_text(i) == keep:
				_metal.select(i)
	for r: Dictionary in controller.station_recipes(station):
		var mat := _selected_metal() if String(r.get("op", "")) == "forge_part" else &""
		var why := controller.recipe_blocker(station, pos, r, mat)
		var n := controller.available(r)
		var row := HandCraftPanel.recipe_row(data, r, why, func() -> void:
			controller.start_recipe(station, pos, r, 1, _selected_metal())
			_dirty = true
			window.refresh(), "Ковать" if String(r.get("op", "")) == "forge_part" else "Сделать")
		if String(r.get("op", "")) != "forge_part" and n > 1:
			var b5 := Button.new()
			b5.text = "×%d" % mini(n, 5)
			b5.disabled = why != ""
			b5.pressed.connect(func() -> void:
				controller.start_recipe(station, pos, r, mini(n, 5))
				_dirty = true
				window.refresh())
			row.add_child(b5)
		_recipes.add_child(row)


func _selected_metal() -> StringName:
	if _metal == null or _metal.selected < 0:
		return &""
	return StringName(_metal.get_item_metadata(_metal.selected))


func _process(delta: float) -> void:
	if _bellows != null and _bellows.button_pressed:
		_pump_t -= delta
		if _pump_t <= 0.0:
			_pump_t = 0.25
			station.pump()
	if _dirty:
		_dirty = false
		_rebuild_recipes()
	var r := station.current_recipe()
	if _progress != null:
		_progress.value = minf(1.0, station.progress()) if not r.is_empty() else 0.0
	if _queue != null:
		_queue.text = "в очереди: %d" % station.queue.size() if not station.queue.is_empty() else ""
	if _gauge != null:
		_gauge.queue_redraw()
	if _cook != null:
		_cook.queue_redraw()
	if _preview != null:
		var pv := controller.assembly_preview(station)
		if pv.is_empty():
			_preview.text = "Положите навершие — станет видно, что получится."
		elif pv.has("error"):
			_preview.text = String(pv["error"]).capitalize()
		else:
			_preview.text = "%s: уровень %d, скорость ×%.1f, урон %.1f, прочность %d, вес %.2f кг · качество: %s" % [
				pv["name"], int(pv["tier"]), float(pv["speed"]), float(pv["damage"]), int(pv["durability"]),
				float(pv["weight"]), controller.data.quality_name(int(pv["quality"]))]
	var water := controller.stations.has_water(pos) if bool(station.def.get("needs_water", false)) else true
	var why := station.blocker({ "water": water })
	if r.is_empty():
		_status.text = "Положите сырьё во вход." if station.is_process() else "Выберите рецепт."
		if station.has_heat() and station.lit():
			_status.text += " Горит: %d °C." % roundi(station.temp)
	elif why != "":
		_status.text = why
		_status.add_theme_color_override("font_color", UiTheme.DANGER)
		return
	else:
		_status.text = "Работает: %s — %d %%" % [controller.data.recipe_name(r), roundi(minf(1.0, station.progress()) * 100.0)]
		if String(r.get("minigame", "")) == "smelt" and not station.auto:
			var hot := float(station.job.get("hot", 0.0))
			if hot > 0.0:
				_status.text += " · в зоне %d %% времени" % roundi(float(station.job.get("green", 0.0)) / hot * 100.0)
	_status.add_theme_color_override("font_color", UiTheme.TEXT_DIM)


## Шкала жара: текущая температура, нужная и зелёная зона [нужная, нужная + 150].
class _Gauge:
	extends Control
	var station: Station

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var mx := maxf(station.max_heat() + float(station.def.get("bellows", 0.0)), 100.0)
		draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.08, 0.08, 0.9))
		var r := station.current_recipe()
		var need := float(r.get("heat", 0.0)) if not r.is_empty() else 0.0
		if need > 0.0:
			var x0 := w * need / mx
			var x1 := w * minf(need + Station.ZONE, mx) / mx
			draw_rect(Rect2(0, 0, x0, h), Color(0.25, 0.3, 0.45, 0.6))
			draw_rect(Rect2(x0, 0, x1 - x0, h), Color(0.25, 0.65, 0.3, 0.75))
			draw_rect(Rect2(x1, 0, w - x1, h), Color(0.6, 0.25, 0.15, 0.6))
		var t := clampf(station.temp / mx, 0.0, 1.0)
		draw_rect(Rect2(w * t - 2, 0, 4, h), Color(1, 0.85, 0.4))
		var font := get_theme_default_font()
		var txt := "%d °C" % roundi(station.temp) + (" (нужно %d)" % roundi(need) if need > 0.0 else "")
		if station.fuel_left > 0.0:
			txt += " · топливо: %d мин" % ceili(station.fuel_left)
		draw_string(font, Vector2(6, h - 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


## Полоса прожарки: сырое / идеально / пережарено / сгорело.
class _CookBar:
	extends Control
	var station: Station

	func _draw() -> void:
		var r := station.current_recipe()
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.08, 0.08, 0.9))
		if r.is_empty() or String(r.get("op", "")) != "cook":
			return
		var c: Dictionary = r.get("cook", {})
		var end := float(c.get("burnt_at", 1.8))
		var zones := [[0.0, float(c.get("perfect_from", 0.9)), Color(0.7, 0.45, 0.45)],
			[float(c.get("perfect_from", 0.9)), float(c.get("perfect_to", 1.25)), Color(0.3, 0.7, 0.3)],
			[float(c.get("perfect_to", 1.25)), end, Color(0.7, 0.5, 0.2)]]
		for z: Array in zones:
			draw_rect(Rect2(w * float(z[0]) / end, 0, w * (float(z[1]) - float(z[0])) / end, h), Color(z[2], 0.7))
		var k := clampf(station.progress() / end, 0.0, 1.0)
		draw_rect(Rect2(w * k - 2, 0, 4, h), Color.WHITE)
		var font := get_theme_default_font()
		draw_string(font, Vector2(6, h - 6), {"under": "Сыровато", "perfect": "Готово!", "over": "Пережаривается",
			"burnt": "Сгорело"}.get(Station.cook_zone(r, station.progress()), ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
