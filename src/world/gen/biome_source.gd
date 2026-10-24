class_name BiomeSource
extends RefCounted
## Биомы из data/biomes.json в плоских массивах для генератора.
##
## Выбор биома: в своей категории рельефа (суша, горы, пик, берег, река, океан) берётся биом
## с ближайшей климатической точкой (температура, влажность, высота). Редкие биомы
## (weirdness > 0) допускаются только там, где |weirdness| не меньше их порога, и тогда
## получают небольшую фору перед обычными.
## Для модификаторов рельефа считаются «мягкие» веса всех биомов категории — так террасы
## каньонов или кочки болот плавно сходят на нет у границы биома.

const CATEGORIES: Array[StringName] = [&"land", &"mountain", &"peak", &"beach", &"river", &"ocean"]
const CAT_LAND := 0
const CAT_MOUNTAIN := 1
const CAT_PEAK := 2
const CAT_BEACH := 3
const CAT_RIVER := 4
const CAT_OCEAN := 5
const KINDS: Array[StringName] = [&"none", &"swamp", &"terrace", &"plateau", &"karst", &"dunes", &"glacier", &"rugged"]
const KIND_COUNT := 8
## Ширина «мягкого» веса в квадратах климатического расстояния.
const SOFT_SIGMA := 0.012
## Фора редкого биома там, где он допустим.
const RARE_BONUS := 0.03

var count := 0
var ids: Array[StringName] = []
var defs: Array[Dictionary] = []
var category := PackedByteArray()
var map_color := PackedColorArray()
var temperature_c := PackedFloat32Array()
var top := PackedInt32Array()
var soil := PackedInt32Array()
var soil_depth := PackedInt32Array()
var subsoil := PackedInt32Array()
var subsoil_depth := PackedInt32Array()
var underwater := PackedInt32Array()
var cliff := PackedInt32Array()
var kind := PackedByteArray()
var strength := PackedFloat32Array()
var snow_cover := PackedByteArray()
var freeze_water := PackedByteArray()
var tree_density := PackedFloat32Array()
## Палитры: index = биом*8 + сезон*2 + (0 трава, 1 листва).
var palettes := PackedColorArray()
## По биому: [PackedInt32Array индексы деревьев, PackedFloat32Array накопленные веса].
var trees: Array = []
## По биому: массив растений [блок, плотность, PackedInt32Array допустимые основания, на воде].
var plants: Array = []
## По биому: массив особенностей [вид, плотность, блок].
var features: Array = []
## По биому: [PackedInt32Array блоки, PackedInt32Array толщины] — слоистые породы.
var bands: Array = []

var _by_cat: Array[PackedInt32Array] = []
var _t := PackedFloat32Array()
var _h := PackedFloat32Array()
var _w := PackedFloat32Array()
var _e := PackedFloat32Array()
var _has_e := PackedByteArray()


func _init(registry: ContentRegistry, tree_index: Dictionary) -> void:
	for c in CATEGORIES.size():
		_by_cat.append(PackedInt32Array())
	for e in registry.get_entries("biomes"):
		var i := count
		count += 1
		ids.append(StringName(e["id"]))
		defs.append(e)
		var cat := CATEGORIES.find(StringName(e["category"]))
		category.append(cat)
		_by_cat[cat].append(i)
		var clim: Dictionary = e["climate"]
		_t.append(clim["temperature"])
		_h.append(clim["humidity"])
		_w.append(clim.get("weirdness", 0.0))
		_has_e.append(1 if clim.has("elevation") else 0)
		_e.append(clim.get("elevation", 0.0))
		map_color.append(e["map_color"])
		temperature_c.append(e["temperature_c"])
		var s: Dictionary = e["surface"]
		top.append(registry.block_num(s["top"]))
		soil.append(registry.block_num(s["soil"]))
		soil_depth.append(s["soil_depth"])
		subsoil.append(registry.block_num(s["subsoil"]) if s.has("subsoil") else -1)
		subsoil_depth.append(s["subsoil_depth"] if s.has("subsoil") else 0)
		underwater.append(registry.block_num(s["underwater"]))
		cliff.append(registry.block_num(s["cliff"]) if s.has("cliff") else -1)
		var terr: Dictionary = e["terrain"]
		kind.append(KINDS.find(StringName(terr["kind"])))
		strength.append(terr["strength"])
		snow_cover.append(1 if e["snow_cover"] else 0)
		freeze_water.append(1 if e["freeze_water"] else 0)
		tree_density.append(e["tree_density"])
		for season in WorldGenSettings.SEASONS:
			palettes.append(e["grass_colors"][season])
			palettes.append(e["foliage_colors"][season])
		var tidx := PackedInt32Array()
		var tw := PackedFloat32Array()
		var total := 0.0
		for t: Dictionary in e["trees"]:
			total += float(t["weight"])
			tidx.append(tree_index[StringName(t["tree"])])
			tw.append(total)
		trees.append([tidx, tw])
		var plist := []
		for p: Dictionary in e["plants"]:
			var on := PackedInt32Array()
			for b: StringName in p["on"]:
				on.append(registry.block_num(b))
			plist.append([registry.block_num(p["block"]), float(p["density"]), on, bool(p["on_water"])])
		plants.append(plist)
		var flist := []
		for f: Dictionary in e["features"]:
			flist.append([StringName(f["kind"]), float(f["density"]), registry.block_num(f["block"]) if f.has("block") else -1])
		features.append(flist)
		var bb := PackedInt32Array()
		var bt := PackedInt32Array()
		for b: Dictionary in e["bands"]:
			bb.append(registry.block_num(b["block"]))
			bt.append(b["thickness"])
		bands.append([bb, bt])


func index_of(id: StringName) -> int:
	return ids.find(id)


func has_category(cat: int) -> bool:
	return not _by_cat[cat].is_empty()


## Ближайший по климату биом категории.
func pick(cat: int, t: float, h: float, w: float, e: float) -> int:
	var best := -1
	var best_d := INF
	for i in _by_cat[cat]:
		var d := _dist(i, t, h, w, e)
		if d < best_d:
			best_d = d
			best = i
	return best


## Веса модификаторов рельефа (KIND_COUNT значений) — мягкая принадлежность к биомам категории.
func soft_kinds(cat: int, t: float, h: float, w: float, e: float, out: PackedFloat32Array, offset: int) -> void:
	for k in KIND_COUNT:
		out[offset + k] = 0.0
	var total := 0.0
	var list := _by_cat[cat]
	var ws := PackedFloat32Array()
	ws.resize(list.size())
	var dmin := INF
	for j in list.size():
		ws[j] = _dist(list[j], t, h, w, e)
		dmin = minf(dmin, ws[j])
	for j in list.size():
		ws[j] = exp(-(ws[j] - dmin) / SOFT_SIGMA) if ws[j] < INF else 0.0
		total += ws[j]
	for j in list.size():
		var i := list[j]
		if kind[i] != 0:
			out[offset + kind[i]] += ws[j] / total * strength[i]


func palette(biome: int, season: int, foliage: bool) -> Color:
	return palettes[biome * 8 + season * 2 + (1 if foliage else 0)]


func _dist(i: int, t: float, h: float, w: float, e: float) -> float:
	var dt := t - _t[i]
	var dh := h - _h[i]
	var d := dt * dt + dh * dh
	if _w[i] > 0.0:
		if absf(w) < _w[i]:
			return INF
		d -= RARE_BONUS
	if _has_e[i] == 1:
		var de := e - _e[i]
		d += de * de * 0.5
	return d
