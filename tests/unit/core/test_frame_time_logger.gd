extends GutTest


func test_empty() -> void:
	assert_eq(FrameTimeLogger.summarize(PackedFloat32Array())["frames"], 0)


func test_summary_values() -> void:
	# 99 кадров по 10 мс и один фриз 50 мс.
	var ms := PackedFloat32Array()
	for i in 99:
		ms.append(10.0)
	ms.append(50.0)
	var s := FrameTimeLogger.summarize(ms)
	assert_eq(s["frames"], 100)
	assert_almost_eq(s["avg_ms"], 10.4, 0.001)
	assert_almost_eq(s["p50_ms"], 10.0, 0.001)
	assert_almost_eq(s["p99_ms"], 10.0, 0.001)
	assert_almost_eq(s["max_ms"], 50.0, 0.001)
	assert_almost_eq(s["low_1pct_fps"], 20.0, 0.001)
	assert_eq(s["stutters"], 1)
