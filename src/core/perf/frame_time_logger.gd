class_name FrameTimeLogger
extends Node
## Пишет frametime каждого кадра и счётчики рендера в user://bench/ (CSV + сводка JSON).
##
## Используется бенчмарк-режимом (`-- --bench=60`) на ПК с видеокартой: в облаке рендер
## headless, и FPS там ничего не значит. Сводку потом вставляют в промт «Проверка производительности».

signal finished(summary: Dictionary)

## Кадры дольше этого считаются фризом (ниже 30 FPS).
const STUTTER_MS := 33.3
const SAMPLE_INTERVAL_SEC := 0.5

@export var label := "bench"
@export var duration_sec := 60.0
@export var warmup_sec := 3.0

var _frame_ms := PackedFloat32Array()
var _samples: Array[Dictionary] = []
var _last_usec := 0
var _start_usec := 0
var _next_sample_sec := 0.0
var _done := false


func _ready() -> void:
	process_priority = 1000
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec


func _process(_delta: float) -> void:
	if _done:
		return
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	var elapsed := (now - _start_usec) / 1_000_000.0
	if elapsed < warmup_sec:
		return
	_frame_ms.append(frame_ms)
	if elapsed >= _next_sample_sec:
		_next_sample_sec = elapsed + SAMPLE_INTERVAL_SEC
		_samples.append(_sample_monitors(elapsed))
	if elapsed >= warmup_sec + duration_sec:
		_finish()


## Сводка по массиву frametime в миллисекундах. Статическая — покрыта тестом.
static func summarize(frame_ms: PackedFloat32Array) -> Dictionary:
	if frame_ms.is_empty():
		return { "frames": 0 }
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	var stutters := 0
	for ms in frame_ms:
		total += ms
		if ms > STUTTER_MS:
			stutters += 1
	var avg := total / frame_ms.size()
	# «1% low» — средний FPS по худшему проценту кадров.
	var worst_count := maxi(1, frame_ms.size() / 100)
	var worst_total := 0.0
	for i in worst_count:
		worst_total += sorted[sorted.size() - 1 - i]
	return {
		"frames": frame_ms.size(),
		"avg_ms": avg,
		"avg_fps": 1000.0 / avg if avg > 0.0 else 0.0,
		"p50_ms": _percentile(sorted, 0.50),
		"p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99),
		"max_ms": sorted[sorted.size() - 1],
		"low_1pct_fps": 1000.0 / (worst_total / worst_count),
		"stutters": stutters,
	}


static func _percentile(sorted: PackedFloat32Array, q: float) -> float:
	var idx := clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[idx]


func _sample_monitors(t: float) -> Dictionary:
	return {
		"t": t,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


func _finish() -> void:
	_done = true
	var summary := summarize(_frame_ms)
	summary["label"] = label
	summary["date"] = Time.get_datetime_string_from_system()
	summary["game_version"] = ProjectSettings.get_setting("application/config/version")
	summary["engine"] = Engine.get_version_info()["string"]
	summary["cpu"] = OS.get_processor_name()
	summary["cpu_threads"] = OS.get_processor_count()
	summary["gpu"] = RenderingServer.get_video_adapter_name()
	summary["gpu_driver"] = RenderingServer.get_video_adapter_api_version()
	summary["renderer"] = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	summary["resolution"] = get_viewport().get_visible_rect().size
	summary["samples"] = _samples

	var dir := "user://bench"
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base := "%s/%s_%s" % [dir, label, stamp]
	var csv := FileAccess.open(base + ".csv", FileAccess.WRITE)
	if csv:
		csv.store_line("frame,ms")
		for i in _frame_ms.size():
			csv.store_line("%d,%.3f" % [i, _frame_ms[i]])
	var js := FileAccess.open(base + ".json", FileAccess.WRITE)
	if js:
		js.store_string(JSON.stringify(summary, "  "))
	print("Бенчмарк '%s': avg %.1f FPS, 1%% low %.1f FPS, p99 %.2f мс → %s" % [
		label, summary["avg_fps"], summary["low_1pct_fps"], summary["p99_ms"],
		ProjectSettings.globalize_path(base + ".json")])
	finished.emit(summary)
