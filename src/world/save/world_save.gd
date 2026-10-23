class_name WorldSave
extends RefCounted
## Папка мира: user://worlds/<папка>/world.json + region/.
## Сид хранится строкой: JSON-числа — double и не вмещают 64-битное целое.

const ROOT := "user://worlds"
const META_FILE := "world.json"
const META_FORMAT := 1

var folder: String
var meta: Dictionary


static func list_worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return out
	for sub in DirAccess.get_directories_at(ROOT):
		var ws := open(ROOT.path_join(sub))
		if ws != null:
			out.append({ "folder": ws.folder, "name": ws.meta.get("name", sub), "last_played": ws.meta.get("last_played", "") })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["last_played"] > b["last_played"])
	return out


static func create(world_name: String, seed_text: String, game_mode: StringName = &"survival", root: String = ROOT) -> WorldSave:
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
		"worldgen": "default",
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
	if typeof(data) != TYPE_DICTIONARY or int(data.get("format", 0)) != META_FORMAT:
		push_warning("WorldSave: %s повреждён или другой версии" % path)
		return null
	var ws := WorldSave.new()
	ws.folder = folder
	ws.meta = data
	return ws


func world_seed() -> int:
	return String(meta["seed"]).to_int()


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
