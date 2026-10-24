class_name BlockTextures
extends RefCounted
## Текстуры блоков (этап 3, раздел 16 ТЗ): атласы Texture2DArray из tools/texgen и таблица
## «блок → слои», по которой шейдер выбирает текстуру грани.
##
## Таблица block_info — RGBA float, ширина 4, высота = число блоков:
##   столбцы 0/1/2 — верх/низ/бок: (первый слой, число вариантов, поворот 0/1, сила свечения);
##   столбец 3 — (map_color.rgb, непрозрачность для прозрачных; < 0 — брать альфу текстуры).
## Если набора нет в манифесте, первый слой −1: шейдер красит грань в map_color (и это видно в логе).

const DIR := "res://assets/textures/generated/"
const MANIFEST := DIR + "blocks_manifest.json"
const FACE_TOP := 0
const FACE_BOTTOM := 1
const FACE_SIDE := 2
const LIQUID_OPACITY := 0.72
## Яркость самосветящихся блоков (лава) при light_emission = 15.
const EMISSION_ENERGY := 2.5

var albedo: TextureLayered
var normal: TextureLayered
var orm: TextureLayered
var block_info: ImageTexture
## Имя набора → { first, count, rotate }.
var sets := {}
var size := 0
var missing: PackedStringArray = []


## Загружает манифест и атласы. Без атласов (например, в тестах без импорта) таблица всё равно
## строится, а текстуры остаются null.
static func load_default(registry: ContentRegistry, load_textures: bool = true) -> BlockTextures:
	var bt := BlockTextures.new()
	bt._load_manifest(MANIFEST)
	if load_textures:
		bt.albedo = load(DIR + "blocks_albedo.webp") as TextureLayered
		bt.normal = load(DIR + "blocks_normal.webp") as TextureLayered
		bt.orm = load(DIR + "blocks_orm.webp") as TextureLayered
	bt.block_info = ImageTexture.create_from_image(bt.build_info_image(registry))
	return bt


func _load_manifest(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("BlockTextures: нет манифеста %s — запусти tools/texgen/texgen.py" % path)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_warning("BlockTextures: битый манифест %s" % path)
		return
	size = int(data.get("size", 0))
	sets = data.get("sets", {})


## Таблица для шейдера (см. описание класса).
func build_info_image(registry: ContentRegistry) -> Image:
	var n := maxi(1, registry.block_count())
	var img := Image.create_empty(4, n, false, Image.FORMAT_RGBAF)
	missing.clear()
	for num in range(1, registry.block_count()):
		var b := registry.block_by_num(num)
		var emission := float(b.light_emission) / 15.0 * EMISSION_ENERGY
		var names := [b.texture_top, b.texture_bottom, b.texture_side]
		for face in 3:
			var s: Dictionary = sets.get(String(names[face]), {})
			if s.is_empty():
				if not missing.has(String(names[face])):
					missing.append(String(names[face]))
				img.set_pixel(face, num, Color(-1, 1, 0, emission))
			else:
				img.set_pixel(face, num, Color(float(s["first"]), float(s["count"]), 1.0 if s["rotate"] else 0.0, emission))
		var opacity := -1.0
		if b.render == &"liquid":
			opacity = LIQUID_OPACITY
		var c := b.map_color
		img.set_pixel(3, num, Color(c.r, c.g, c.b, opacity))
	if not missing.is_empty() and not sets.is_empty():
		push_warning("BlockTextures: нет текстур для наборов %s — перегенерируй tools/texgen" % ", ".join(missing))
	return img


## Слой и число вариантов набора (для тестов и инструментов).
func set_info(set_name: String) -> Dictionary:
	return sets.get(set_name, {})
