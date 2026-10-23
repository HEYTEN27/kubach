extends GutTest


func test_actions_registered_with_physical_keys() -> void:
	for action in [&"move_forward", &"jump", &"attack", &"toggle_camera", &"debug_overlay", &"hotbar_9"]:
		assert_true(InputMap.has_action(action), String(action))
	var ev: InputEventKey = InputMap.action_get_events(&"move_forward")[0]
	assert_eq(ev.physical_keycode, KEY_W, "W по положению — работает и на русской раскладке")
	assert_eq(ev.keycode, KEY_NONE)
	var mb: InputEventMouseButton = InputMap.action_get_events(&"attack")[0]
	assert_eq(mb.button_index, MOUSE_BUTTON_LEFT)


func test_f5_toggles_camera_and_space_jumps() -> void:
	var f5: InputEventKey = InputMap.action_get_events(&"toggle_camera")[0]
	assert_eq(f5.physical_keycode, KEY_F5)
	var space: InputEventKey = InputMap.action_get_events(&"jump")[0]
	assert_eq(space.physical_keycode, KEY_SPACE)
