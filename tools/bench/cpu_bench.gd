extends Node
## CPU-бенчмарки без видеокарты (запускается сценой cpu_bench.tscn — так доступны автозагрузки). Каждый файл в tools/bench/cases/ — класс с полями
## `name`, `iterations` и методами `setup()`, `run()`, `teardown()`.
## Меряется медиана времени `run()`; результат пишется в build/bench/cpu_bench.json и
## сравнивается с tools/bench/baseline.json (порог REGRESSION_PCT).

const CASES_DIR := "res://tools/bench/cases"
const BASELINE := "res://tools/bench/baseline.json"
const OUT := "res://build/bench/cpu_bench.json"
const REGRESSION_PCT := 25.0


func _ready() -> void:
	# Отложенно: кейсам нужно добавлять узлы в дерево, а в _ready корень ещё занят.
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var results := {}
	var files := Array(DirAccess.get_files_at(CASES_DIR)).filter(func(f: String) -> bool: return f.ends_with(".gd"))
	files.sort()
	for file: String in files:
		var bench: Object = load(CASES_DIR.path_join(file)).new()
		bench.setup()
		var times := PackedFloat64Array()
		for i in bench.iterations:
			var t0 := Time.get_ticks_usec()
			bench.run()
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
		bench.teardown()
		times.sort()
		var median := times[times.size() / 2]
		results[bench.name] = { "median_ms": median, "min_ms": times[0], "max_ms": times[-1], "iterations": bench.iterations }
		print("%-32s медиана %8.3f мс  (мин %.3f, макс %.3f, n=%d)" % [bench.name, median, times[0], times[-1], bench.iterations])
		if bench is Node:
			bench.free()

	var report := { "date": Time.get_datetime_string_from_system(), "cpu": OS.get_processor_name(),
		"threads": OS.get_processor_count(), "engine": Engine.get_version_info()["string"], "results": results }
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()

	if "--update-baseline" in args:
		var b := FileAccess.open(BASELINE, FileAccess.WRITE)
		b.store_string(JSON.stringify(report, "  "))
		b.close()
		print("Эталон обновлён: ", BASELINE)
		get_tree().quit(0)
		return
	get_tree().quit(_compare(results, "--strict" in args))


func _compare(results: Dictionary, strict: bool) -> int:
	if not FileAccess.file_exists(BASELINE):
		print("Эталона нет (scripts/bench.sh --update-baseline создаст).")
		return 0
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE)).get("results", {})
	var regressed := 0
	for name: String in results:
		if not base.has(name):
			continue
		var was: float = base[name]["median_ms"]
		var now: float = results[name]["median_ms"]
		var pct := (now - was) / maxf(was, 0.0001) * 100.0
		if pct > REGRESSION_PCT:
			regressed += 1
			print("  ✗ %s медленнее на %.0f%% (%.3f → %.3f мс)" % [name, pct, was, now])
	if regressed == 0:
		print("Регрессий нет (порог %.0f%%)." % REGRESSION_PCT)
	return 1 if strict and regressed > 0 else 0
