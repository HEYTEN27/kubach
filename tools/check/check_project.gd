extends Node
## Проверка проекта (запускается из scripts/check.sh как сцена, чтобы были доступны автозагрузки):
##   1) каждый наш .gd компилируется (addons/ не трогаем);
##   2) Registry загружает res://data без ошибок.
## Код выхода 1 — есть ошибки.

const SCRIPT_ROOTS: PackedStringArray = ["res://src", "res://tests", "res://tools"]


func _ready() -> void:
	var failed := 0
	var scripts := PackedStringArray()
	for root in SCRIPT_ROOTS:
		_collect(root, scripts)
	for path in scripts:
		var s := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if s == null or not s.can_instantiate():
			print("✗ не компилируется: ", path)
			failed += 1
	print("  скриптов проверено: %d, с ошибками: %d" % [scripts.size(), failed])

	var reg := ContentRegistry.new()
	if reg.load_all():
		print("OK: data/ — категорий %d, блоков %d (с воздухом)" % [reg.categories().size(), reg.block_count()])
	else:
		failed += 1
	for e in reg.errors:
		print("✗ data: ", e)
	for w in reg.warnings:
		print("  предупреждение data: ", w)
	reg.free()
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), out)
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "gd":
			out.append(dir.path_join(f))
