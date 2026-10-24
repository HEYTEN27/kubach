class_name SettingsScreen
extends PanelContainer
## Экран настроек (раздел 19 ТЗ). Вкладки и элементы строятся по data/settings.json:
## bool — переключатель, int/float — ползунок, enum — список. Настройки с полем stage > 4
## показываются с пометкой «с этапа N»: значение сохраняется, а работать начнёт на этом этапе.
## Вкладка «Управление» дополнительно содержит переназначение клавиш (клавиатура, мышь, геймпад)
## с проверкой конфликтов. Изменения применяются сразу и сохраняются при закрытии.

signal closed()

const SECTIONS := [
	["graphics", "Графика"], ["display", "Экран"], ["audio", "Звук"], ["controls", "Управление"],
	["interface", "Интерфейс"], ["accessibility", "Доступность"], ["gameplay", "Игра"],
]
const CURRENT_STAGE := 4

var _tabs: TabContainer
var _widgets := {}   # id -> [Control, def]
var _rebind_action: StringName = &""
var _rebind_index := -1
var _rebind_label: Label
var _bind_rows: VBoxContainer
var _updating := false


func _ready() -> void:
	custom_minimum_size = Vector2(900, 620)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var title := Label.new()
	title.text = "Настройки"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	for sec: Array in SECTIONS:
		_tabs.add_child(_build_section(sec[0], sec[1]))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	var reset := Button.new()
	reset.text = "Сбросить раздел"
	reset.pressed.connect(func() -> void:
		var sec: String = SECTIONS[_tabs.current_tab][0]
		Settings.reset_section(sec)
		_sync_all())
	bottom.add_child(reset)
	var done := Button.new()
	done.text = "Готово"
	done.custom_minimum_size.x = 140
	done.pressed.connect(close)
	bottom.add_child(done)
	Settings.setting_changed.connect(_on_setting_changed)
	_sync_all()


func close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _build_section(section: String, title: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for d in Settings.definitions(section):
		list.add_child(_row(d))
	if section == "controls":
		list.add_child(HSeparator.new())
		var t := Label.new()
		t.text = "Клавиши (нажмите на привязку, затем новую клавишу, кнопку мыши или геймпада; Esc — отмена)"
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(t)
		_rebind_label = Label.new()
		_rebind_label.add_theme_color_override("font_color", UiTheme.accent())
		list.add_child(_rebind_label)
		_bind_rows = VBoxContainer.new()
		list.add_child(_bind_rows)
		_build_bindings()
	return scroll


func _row(d: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	var stage := int(d.get("stage", 0))
	name_label.text = String(d["name"]["ru"])
	if stage > CURRENT_STAGE:
		name_label.text += "  (с этапа %d)" % stage
		name_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	name_label.custom_minimum_size.x = 360
	name_label.tooltip_text = String(d.get("hint", ""))
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_label)
	var id := String(d["id"])
	var w: Control
	match String(d["type"]):
		"bool":
			var cb := CheckButton.new()
			cb.toggled.connect(func(on: bool) -> void: _apply_value(id, on))
			w = cb
		"int", "float":
			var box := HBoxContainer.new()
			var sl := HSlider.new()
			sl.min_value = float(d["min"])
			sl.max_value = float(d["max"])
			sl.step = float(d["step"]) if String(d["type"]) == "float" else maxf(1.0, float(d["step"]))
			sl.custom_minimum_size.x = 280
			var val := Label.new()
			val.custom_minimum_size.x = 60
			sl.value_changed.connect(func(v: float) -> void:
				val.text = _fmt(d, v)
				_apply_value(id, int(v) if String(d["type"]) == "int" else v))
			box.add_child(sl)
			box.add_child(val)
			w = box
		"enum":
			var ob := OptionButton.new()
			for o: Dictionary in d["options"]:
				ob.add_item(String(o["name"]["ru"]))
				ob.set_item_metadata(ob.item_count - 1, String(o["value"]))
			ob.item_selected.connect(func(i: int) -> void: _apply_value(id, ob.get_item_metadata(i)))
			ob.custom_minimum_size.x = 260
			w = ob
	if d.get("hint", "") != "":
		var h := Label.new()
		h.text = "ⓘ"
		h.tooltip_text = String(d["hint"])
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(w)
		row.add_child(h)
	else:
		row.add_child(w)
	_widgets[id] = [w, d]
	return row


static func _fmt(d: Dictionary, v: float) -> String:
	if String(d["type"]) == "int":
		return str(int(v))
	return "%.2f" % v


func _apply_value(id: String, value: Variant) -> void:
	if _updating:
		return
	Settings.set_value(id, value)
	Audio.play_ui("ui/click")


func _on_setting_changed(id: String, _value: Variant) -> void:
	# Пресет графики меняет сразу много значений — перечитываем всё.
	if id == "graphics_preset" or Settings.definition(id).get("preset_key", false):
		_sync_all()


func _sync_all() -> void:
	_updating = true
	for id: String in _widgets:
		var w: Control = _widgets[id][0]
		var d: Dictionary = _widgets[id][1]
		var v: Variant = Settings.get_value(id)
		match String(d["type"]):
			"bool":
				(w as CheckButton).button_pressed = bool(v)
			"int", "float":
				var sl := w.get_child(0) as HSlider
				sl.value = float(v)
				(w.get_child(1) as Label).text = _fmt(d, float(v))
			"enum":
				var ob := w as OptionButton
				for i in ob.item_count:
					if String(ob.get_item_metadata(i)) == str(v):
						ob.select(i)
	_updating = false
	if _bind_rows != null:
		_build_bindings()


func _build_bindings() -> void:
	for c in _bind_rows.get_children():
		c.queue_free()
	for e in Registry.get_entries("input_bindings"):
		if not e.get("rebindable", true):
			continue
		var action := StringName(e["id"])
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = String(e["name"]["ru"])
		l.custom_minimum_size.x = 360
		row.add_child(l)
		var events := InputMap.action_get_events(action) if InputMap.has_action(action) else []
		for i in maxi(events.size(), 1) + 1:
			var b := Button.new()
			b.custom_minimum_size.x = 130
			if i < events.size():
				b.text = Controls.event_label(events[i])
				b.tooltip_text = "ЛКМ — заменить, ПКМ — удалить"
			else:
				b.text = "+"
				b.tooltip_text = "Добавить привязку"
			b.gui_input.connect(_bind_button_input.bind(action, i))
			row.add_child(b)
		var def := Button.new()
		def.text = "↺"
		def.tooltip_text = "По умолчанию"
		def.pressed.connect(func() -> void:
			Settings.bindings.erase(String(action))
			Controls.reapply()
			_build_bindings())
		row.add_child(def)
		_bind_rows.add_child(row)


func _bind_button_input(event: InputEvent, action: StringName, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		var evs := InputMap.action_get_events(action)
		if index < evs.size():
			evs.remove_at(index)
			_store(action, evs)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_rebind_action = action
		_rebind_index = index
		_rebind_label.text = "Нажмите новую клавишу для «%s»…" % Registry.get_entry("input_bindings", action)["name"]["ru"]
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _rebind_action == &"":
		return
	var ev: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_rebind_action = &""
			_rebind_label.text = "Отменено"
			get_viewport().set_input_as_handled()
			return
		ev = InputEventKey.new()
		(ev as InputEventKey).physical_keycode = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	elif event is InputEventMouseButton and event.pressed and event.button_index != MOUSE_BUTTON_LEFT:
		ev = InputEventMouseButton.new()
		(ev as InputEventMouseButton).button_index = event.button_index
	elif event is InputEventJoypadButton and event.pressed:
		ev = InputEventJoypadButton.new()
		(ev as InputEventJoypadButton).button_index = event.button_index
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		ev = InputEventJoypadMotion.new()
		(ev as InputEventJoypadMotion).axis = event.axis
		(ev as InputEventJoypadMotion).axis_value = signf(event.axis_value)
	if ev == null:
		return
	get_viewport().set_input_as_handled()
	var evs := InputMap.action_get_events(_rebind_action)
	if _rebind_index < evs.size():
		evs[_rebind_index] = ev
	else:
		evs.append(ev)
	var clash := Controls.conflicts(_rebind_action, ev)
	_store(_rebind_action, evs)
	if clash.is_empty():
		_rebind_label.text = "Назначено: %s" % Controls.event_label(ev)
	else:
		var names := PackedStringArray()
		for a in clash:
			names.append(String(Registry.get_entry("input_bindings", a).get("name", {}).get("ru", a)))
		_rebind_label.text = "Назначено: %s. Внимание: эта клавиша уже занята — %s" % [Controls.event_label(ev), ", ".join(names)]
	_rebind_action = &""


func _store(action: StringName, evs: Array) -> void:
	var out := []
	for e: InputEvent in evs:
		out.append(Controls.event_to_string(e))
	Settings.bindings[String(action)] = out
	Controls.set_events(action, out)
	_build_bindings.call_deferred()
