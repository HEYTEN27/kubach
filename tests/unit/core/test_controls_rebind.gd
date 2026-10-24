extends GutTest
## Переназначение клавиш: строки событий, конфликты, геймпад.


func after_each() -> void:
	Settings.bindings.clear()
	Controls.reapply()


func test_event_string_roundtrip() -> void:
	for s in ["key:%d" % KEY_W, "mouse:2", "joy:0", "axis:1:-1"]:
		var ev := Controls.string_to_event(s)
		assert_not_null(ev, s)
		assert_eq(Controls.event_to_string(ev), s)


func test_gamepad_defaults_registered() -> void:
	var found := false
	for e in InputMap.action_get_events(&"jump"):
		if e is InputEventJoypadButton:
			found = true
	assert_true(found, "прыжок — кнопка A геймпада")
	assert_true(InputMap.has_action(&"look_left"))
	assert_true(InputMap.has_action(&"inventory"))


func test_rebind_and_conflict() -> void:
	Controls.set_events(&"jump", ["key:%d" % KEY_J])
	var evs := InputMap.action_get_events(&"jump")
	assert_eq(evs.size(), 1)
	assert_eq((evs[0] as InputEventKey).physical_keycode, KEY_J)
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	assert_has(Controls.conflicts(&"jump", w), &"move_forward")


func test_settings_bindings_applied_on_reapply() -> void:
	Settings.bindings["drop_item"] = ["key:%d" % KEY_G]
	Controls.reapply()
	var evs := InputMap.action_get_events(&"drop_item")
	assert_eq(Controls.event_to_string(evs[0]), "key:%d" % KEY_G)
