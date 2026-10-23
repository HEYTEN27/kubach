extends GutTest
## Аудио — только реальные файлы: нет файла — тихий пропуск (раздел 0, правило 3).


func test_missing_sound_is_skipped() -> void:
	assert_false(Audio.play_at("test/no_such_sound", Vector3.ZERO))
	assert_eq(Audio.streams_for("test/no_such_sound"), [])


func test_block_sound_groups_match_manifest_naming() -> void:
	# Ключи, которые слушают события, должны совпадать с MANIFEST.md.
	var manifest := FileAccess.get_file_as_string("res://assets/audio/MANIFEST.md")
	for e in Registry.get_entries("blocks"):
		var group := String(e["sounds"])
		if group == "none":
			continue
		assert_string_contains(manifest, "footsteps/%s_" % group)
		assert_string_contains(manifest, "blocks/%s_break_" % group)
		assert_string_contains(manifest, "blocks/%s_place_" % group)
