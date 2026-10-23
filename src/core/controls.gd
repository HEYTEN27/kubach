extends Node
## Автозагрузка `Controls`: регистрирует действия InputMap из data/input_bindings.json.
## Клавиши привязываются по физическому положению (physical_keycode): WASD работает
## при любой раскладке, в том числе русской.


func _ready() -> void:
	var reg := get_node_or_null(^"/root/Registry") as ContentRegistry
	if reg == null:
		return
	apply_bindings(reg)


static func apply_bindings(reg: ContentRegistry) -> void:
	for e in reg.get_entries("input_bindings"):
		var action := StringName(e["id"])
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for key_name: String in e["keys"]:
			var code := OS.find_keycode_from_string(key_name)
			if code == KEY_NONE:
				push_warning("Controls: неизвестная клавиша '%s' у действия %s" % [key_name, action])
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
		for button: int in e["mouse_buttons"]:
			var mb := InputEventMouseButton.new()
			mb.button_index = button as MouseButton
			InputMap.action_add_event(action, mb)
