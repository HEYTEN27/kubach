class_name WorldSave
extends RefCounted
## Папка мира: user://worlds/<папка>/world.json + region/ + preview.png + backups/.
## Сид хранится строкой: JSON-числа — double и не вмещают 64-битное целое.
##
## Формат world.json: 1 — этапы 1–3; 2 — этап 4 (инвентарь, внешность, предметы на земле,
## сезон). Старые сохранения открываются и мигрируют (migrate()).

const ROOT := "user://worlds"
const META_FILE := "world.json"
const META_FORMAT := 2
const PREVIEW := "preview.png"
const BACKUPS := "backups"

var folder: String
var meta: Dictionary


static func list_worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return out
	for sub in DirAccess.get_directories_at(ROOT):
		var ws := open(ROOT.path_join(sub))
		if ws != null:
			out.append({ "folder": ws.folder, "name": ws.meta.get("name", sub), "last_played": ws.meta.get("last_played", ""),
				"play_time_sec": float(ws.meta.get("play_time_sec", 0.0)), "game_mode": ws.meta.get("game_mode", "survival"),
				"season": ws.meta.get("season", (ws.meta.get("worldgen") as Dictionary).get("start_season", "summer")
					if ws.meta.get("worldgen") is Dictionary else "summer"),
				"day": int(ws.meta.get("day", 1)), "preview": ws.folder.path_join(PREVIEW) })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["last_played"] > b["last_played"])
	return out


static func create(world_name: String, seed_text: String, game_mode: StringName = &"survival", root: String = ROOT,
		settings: WorldGenSettings = null) -> WorldSave:
	var ws := WorldSave.new()
	var base := _slug(world_name)
	var folder := root.path_join(base)
	var n := 2
	while DirAccess.dir_exists_absolute(folder):
		folder = root.path_join("%s_%d" % [base, n])
		n += 1
	ws.folder = folder
	var now := Time.get_datetime_string_from_system()
	ws.meta = {
		"format": META_FORMAT,
		"name": world_name,
		"seed_text": seed_text,
		"seed": str(WorldSeed.from_text(seed_text)),
		"worldgen": (settings if settings != null else WorldGenSettings.new()).to_dict(),
		"game_mode": String(game_mode),
		"created": now,
		"last_played": now,
		"play_time_sec": 0.0,
		"player": {},
	}
	DirAccess.make_dir_recursive_absolute(ws.region_dir())
	ws.save_meta()
	return ws


static func open(folder: String) -> WorldSave:
	var path := folder.path_join(META_FILE)
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("format", 0)) < 1 or int(data.get("format", 0)) > META_FORMAT:
		push_warning("WorldSave: %s повреждён или из более новой версии игры" % path)
		return null
	migrate(data)
	var ws := WorldSave.new()
	ws.folder = folder
	ws.meta = data
	return ws


## Миграции формата world.json до текущего (раздел 21: версия формата и миграции).
static func migrate(data: Dictionary) -> void:
	var fmt := int(data.get("format", 1))
	if fmt < 2:
		# 1 → 2: у игрока появились инвентарь и внешность (пусто — стартовые по умолчанию).
		var p: Dictionary = data.get("player", {})
		data["player"] = p
		data["dropped"] = []
		data["day"] = 1
		fmt = 2
	data["format"] = fmt


## Копия мира перед автосохранением: backups/1 — самая свежая, хранится keep штук.
func backup(keep: int = 3) -> void:
	var root := folder.path_join(BACKUPS)
	DirAccess.make_dir_recursive_absolute(root)
	var oldest := root.path_join(str(keep))
	if DirAccess.dir_exists_absolute(oldest):
		_remove_tree(oldest)
	for i in range(keep - 1, 0, -1):
		var src := root.path_join(str(i))
		if DirAccess.dir_exists_absolute(src):
			DirAccess.rename_absolute(src, root.path_join(str(i + 1)))
	var dst := root.path_join("1")
	DirAccess.make_dir_recursive_absolute(dst.path_join("region"))
	if FileAccess.file_exists(folder.path_join(META_FILE)):
		DirAccess.copy_absolute(folder.path_join(META_FILE), dst.path_join(META_FILE))
	if DirAccess.dir_exists_absolute(region_dir()):
		for f in DirAccess.get_files_at(region_dir()):
			if f.ends_with(".kbr"):
				DirAccess.copy_absolute(region_dir().path_join(f), dst.path_join("region").path_join(f))


static func _remove_tree(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## Удалить мир целиком (меню «Загрузить» → «Удалить»).
static func delete_world(p_folder: String) -> void:
	if DirAccess.dir_exists_absolute(p_folder):
		_remove_tree(p_folder)


func world_seed() -> int:
	return String(meta["seed"]).to_int()


## Настройки генерации мира (сохранения этапа 1 хранили здесь строку — тогда значения по умолчанию).
func gen_settings() -> WorldGenSettings:
	var d: Variant = meta.get("worldgen", {})
	return WorldGenSettings.from_dict(d if d is Dictionary else {})


func region_dir() -> String:
	return folder.path_join("region")


func save_meta() -> Error:
	meta["last_played"] = Time.get_datetime_string_from_system()
	var tmp := folder.path_join(META_FILE + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	var path := folder.path_join(META_FILE)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Безопасное имя папки: латиница/цифры/кириллица, остальное — «_».
static func _slug(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		var c := ch.unicode_at(0)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 0x400 and c <= 0x4FF)
		out += ch if ok else "_"
	if out.is_empty() or out.replace("_", "").is_empty():
		out = "world"
	return out.substr(0, 48)
