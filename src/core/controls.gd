extends Node
## Автозагрузка `Controls`: регистрирует действия InputMap из data/input_bindings.json и
## накладывает переназначения игрока (Settings.bindings). Клавиши привязываются по физическому
## положению (physical_keycode): WASD работает при любой раскладке, в том числе русской.
##
## Событие в настройках — строка: "key:<physical keycode>", "mouse:<кнопка>",
## "joy:<кнопка>", "axis:<ось>:<направление ±1>".

## Мёртвая зона осей геймпада (настройка pad_deadzone).
var deadzone := 0.2


func _ready() -> void:
	reapply()


## Перерегистрировать все действия: данные по умолчанию + переназначения игрока.
func reapply() -> void:
	var reg := get_node_or_null(^"/root/Registry") as ContentRegistry
	if reg == null:
		return
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		deadzone = float(settings.call(&"get_value", "pad_deadzone"))
	apply_bindings(reg, deadzone)
	if settings != null:
		var b: Dictionary = settings.get(&"bindings")
		for action: String in b:
			set_events(StringName(action), b[action])


static func apply_bindings(reg: ContentRegistry, p_deadzone: float = 0.2) -> void:
	for e in reg.get_entries("input_bindings"):
		var action := StringName(e["id"])
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, p_deadzone)
		InputMap.action_set_deadzone(action, p_deadzone)
		for ev in default_events(e):
			InputMap.action_add_event(action, ev)


## События действия по умолчанию (из записи input_bindings).
static func default_events(e: Dictionary) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	for key_name: String in e.get("keys", []):
		var code := OS.find_keycode_from_string(key_name)
		if code == KEY_NONE:
			push_warning("Controls: неизвестная клавиша '%s' у действия %s" % [key_name, e["id"]])
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		out.append(ev)
	for button: int in e.get("mouse_buttons", []):
		var mb := InputEventMouseButton.new()
		mb.button_index = button as MouseButton
		out.append(mb)
	for button: int in e.get("joy_buttons", []):
		var jb := InputEventJoypadButton.new()
		jb.button_index = button as JoyButton
		out.append(jb)
	for ax: Dictionary in e.get("joy_axes", []):
		var jm := InputEventJoypadMotion.new()
		jm.axis = int(ax["axis"]) as JoyAxis
		jm.axis_value = float(ax["dir"])
		out.append(jm)
	return out


## Заменить события действия списком строк (переназначение).
func set_events(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for s: Variant in events:
		var ev := string_to_event(String(s))
		if ev != null:
			InputMap.action_add_event(action, ev)


static func event_to_string(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return "key:%d" % code
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "joy:%d" % ev.button_index
	if ev is InputEventJoypadMotion:
		return "axis:%d:%d" % [ev.axis, 1 if ev.axis_value > 0.0 else -1]
	return ""


static func string_to_event(s: String) -> InputEvent:
	var p := s.split(":")
	match p[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(p[1]) as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(p[1]) as MouseButton
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = int(p[1]) as JoyButton
			return j
		"axis":
			if p.size() < 3:
				return null
			var a := InputEventJoypadMotion.new()
			a.axis = int(p[1]) as JoyAxis
			a.axis_value = float(int(p[2]))
			return a
	return null


## Подпись события для экрана управления.
static func event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		var with_layout := DisplayServer.keyboard_get_keycode_from_physical(code as Key)
		return OS.get_keycode_string(with_layout if with_layout != KEY_NONE else code)
	if ev is InputEventMouseButton:
		return { 1: "ЛКМ", 2: "ПКМ", 3: "СКМ", 4: "Колесо ↑", 5: "Колесо ↓" }.get(ev.button_index, "Мышь %d" % ev.button_index)
	if ev is InputEventJoypadButton:
		return { 0: "Pad A", 1: "Pad B", 2: "Pad X", 3: "Pad Y", 4: "Pad Back", 6: "Pad Start", 7: "Pad L3", 8: "Pad R3",
			9: "Pad LB", 10: "Pad RB", 11: "Pad ↑", 12: "Pad ↓", 13: "Pad ←", 14: "Pad →" }.get(ev.button_index, "Pad %d" % ev.button_index)
	if ev is InputEventJoypadMotion:
		var names := { 0: "Левый стик X", 1: "Левый стик Y", 2: "Правый стик X", 3: "Правый стик Y", 4: "LT", 5: "RT" }
		return "%s %s" % [names.get(ev.axis, "Ось %d" % ev.axis), "+" if ev.axis_value > 0 else "−"]
	return "?"


## Какие ещё действия используют это событие (конфликты при переназначении).
static func conflicts(action: StringName, ev: InputEvent) -> Array[StringName]:
	var out: Array[StringName] = []
	var key := event_to_string(ev)
	for a in InputMap.get_actions():
		if a == action or String(a).begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(a):
			if event_to_string(e) == key:
				out.append(a)
	return out
