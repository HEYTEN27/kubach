class_name TerrainGenerator
extends RefCounted
## Генератор рельефа (этап 1): высота из нескольких слоёв шума, слои пород, вода до уровня моря.
## Все параметры — в data/worldgen.json. Чистая функция от (сид, координаты колонны):
## один и тот же сид даёт один и тот же мир независимо от порядка генерации.
##
## Потокобезопасен после создания: шумы FastNoiseLite только читаются.

const MAX_RUNS := 8

var world_seed: int
var sea_level: int
var bedrock_top: int

var _p: Dictionary
var _n_continental: FastNoiseLite
var _n_erosion: FastNoiseLite
var _n_ridges: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_strata: FastNoiseLite
var _spline_x := PackedFloat64Array()
var _spline_y := PackedFloat64Array()

var _b_bedrock: int
var _b_surface: int
var _b_soil: int
var _b_beach: int
var _b_shallow: int
var _b_deep: int
var _b_cliff: int
var _b_upper: int
var _b_lower: int
var _b_fluid: int


func _init(p_seed: int, registry: ContentRegistry, preset: StringName = &"default") -> void:
	world_seed = p_seed
	_p = registry.get_entry("worldgen", preset)
	assert(not _p.is_empty(), "нет пресета генерации '%s'" % preset)
	sea_level = _p["sea_level"]
	bedrock_top = _p["bedrock_top"]
	var noise: Dictionary = _p["noise"]
	_n_continental = _make_noise(1, noise["continental"], FastNoiseLite.FRACTAL_FBM)
	_n_erosion = _make_noise(2, noise["erosion"], FastNoiseLite.FRACTAL_FBM)
	_n_ridges = _make_noise(3, noise["ridges"], FastNoiseLite.FRACTAL_RIDGED)
	_n_detail = _make_noise(4, noise["detail"], FastNoiseLite.FRACTAL_FBM)
	_n_strata = _make_noise(5, noise["strata"], FastNoiseLite.FRACTAL_FBM)
	for pt: Dictionary in _p["height_spline"]:
		_spline_x.append(pt["x"])
		_spline_y.append(pt["y"])

	var layers: Dictionary = _p["layers"]
	_b_bedrock = registry.block_num(_p["bedrock_block"])
	_b_surface = registry.block_num(layers["surface"])
	_b_soil = registry.block_num(layers["soil"])
	_b_beach = registry.block_num(layers["beach"])
	_b_shallow = registry.block_num(layers["shallow_floor"])
	_b_deep = registry.block_num(layers["deep_floor"])
	_b_cliff = registry.block_num(layers["cliff"])
	_b_upper = registry.block_num(layers["upper_stone"])
	_b_lower = registry.block_num(layers["lower_stone"])
	_b_fluid = registry.block_num(layers["fluid"])


## Высота поверхности (Y верхнего твёрдого блока) в точке.
func surface_height(x: int, z: int) -> int:
	return floori(_height(float(x), float(z)))


func generate_column(cpos: Vector2i) -> ChunkColumn:
	var col := ChunkColumn.new(cpos)
	var bx := cpos.x * 16
	var bz := cpos.y * 16

	# Высоты 18×18 (с соседями по краю) — для крутизны склонов.
	var heights := PackedInt32Array()
	heights.resize(324)
	for hz in 18:
		for hx in 18:
			heights[hx + hz * 18] = floori(_height(float(bx + hx - 1), float(bz + hz - 1)))

	# Для каждого столба 16×16 — «прогоны» по высоте: (верхняя Y включительно, блок), снизу вверх.
	var tops := PackedInt32Array()
	var blks := PackedInt32Array()
	tops.resize(256 * MAX_RUNS)
	blks.resize(256 * MAX_RUNS)
	var layers: Dictionary = _p["layers"]
	var soil_depth: int = layers["soil_depth"]
	var beach_band: int = layers["beach_band"]
	var deep_depth: int = layers["deep_floor_depth"]
	var upper_depth: int = layers["upper_stone_depth"]
	var upper_noise: float = layers["upper_stone_noise"]
	var cliff_slope: int = _p["cliff_slope"]

	for lz in 16:
		for lx in 16:
			var hi := (lx + 1) + (lz + 1) * 18
			var h := heights[hi]
			var slope := maxi(maxi(absi(h - heights[hi - 1]), absi(h - heights[hi + 1])),
				maxi(absi(h - heights[hi - 18]), absi(h - heights[hi + 18])))
			var top := _b_surface
			var soil := _b_soil
			var depth := soil_depth
			if h < sea_level - deep_depth:
				top = _b_deep
				soil = _b_deep
				depth = 3
			elif h < sea_level - 1:
				top = _b_shallow
				soil = _b_shallow
				depth = 3
			elif h <= sea_level + beach_band:
				top = _b_beach
				soil = _b_beach
			elif slope >= cliff_slope:
				top = _b_cliff
				soil = _b_cliff
			var soil_bottom := h - depth
			var upper_bottom := soil_bottom - upper_depth + floori(_n_strata.get_noise_2d(bx + lx, bz + lz) * upper_noise)

			var c := (lx + lz * 16) * MAX_RUNS
			var n := 0
			var prev := WorldConst.MIN_Y - 1
			# Прогон пропускается, если он пустой (не выше предыдущего).
			for run in [
				[bedrock_top, _b_bedrock],
				[upper_bottom, _b_lower],
				[soil_bottom, _b_upper],
				[h - 1, soil],
				[h, top],
				[sea_level, _b_fluid],
				[WorldConst.MAX_Y - 1, 0],
			]:
				var t: int = mini(run[0], WorldConst.MAX_Y - 1)
				if t <= prev:
					continue
				tops[c + n] = t
				blks[c + n] = run[1]
				n += 1
				prev = t
			# Сентинел на случай, если последний прогон не дошёл до верха.
			if prev < WorldConst.MAX_Y - 1:
				tops[c + n] = WorldConst.MAX_Y - 1
				blks[c + n] = 0

	_fill_sections(col, tops, blks)
	return col


func _fill_sections(col: ChunkColumn, tops: PackedInt32Array, blks: PackedInt32Array) -> void:
	var count := WorldConst.SECTIONS_PER_COLUMN
	var sec_block := PackedInt32Array()
	sec_block.resize(count)
	var mixed := PackedByteArray()
	mixed.resize(count)

	# Проход по столбам: секция однородна, если внутри неё нет границы прогона
	# и на её нижней Y во всех столбах один и тот же блок.
	for c in 256:
		var base := c * MAX_RUNS
		var r := 0
		for si in count:
			var y0 := WorldConst.MIN_Y + si * 16
			while tops[base + r] < y0:
				r += 1
			var b := blks[base + r]
			if c == 0:
				sec_block[si] = b
			elif sec_block[si] != b:
				mixed[si] = 1
			if tops[base + r] < y0 + 15:
				mixed[si] = 1

	for si in count:
		if mixed[si] == 0:
			if sec_block[si] != 0:
				col.sections[si] = ChunkSection.filled(sec_block[si])
			continue
		var y0 := WorldConst.MIN_Y + si * 16
		var arr := PackedInt32Array()
		arr.resize(WorldConst.SECTION_VOLUME)
		for c in 256:
			var base := c * MAX_RUNS
			var r := 0
			while tops[base + r] < y0:
				r += 1
			# c = lx + lz*16, а индекс в секции = lx | lz<<4 | ly<<8 — совпадает с c для ly = 0.
			for ly in 16:
				if tops[base + r] < y0 + ly:
					r += 1
				arr[c | (ly << 8)] = blks[base + r]
		var s := ChunkSection.new()
		s.blocks = arr
		if not s.try_compact() or s.uniform != 0:
			col.sections[si] = s


func _height(x: float, z: float) -> float:
	var c := _n_continental.get_noise_2d(x, z)
	var base := _spline(c)
	var me: Dictionary = _p["mountain_erosion"]
	var m := smoothstep(float(me["start"]), float(me["full"]), _n_erosion.get_noise_2d(x, z))
	# Горы только на суше.
	m *= smoothstep(-0.12, 0.05, c)
	var ridge := (_n_ridges.get_noise_2d(x, z) + 1.0) * 0.5
	var detail := _n_detail.get_noise_2d(x, z) * float(_p["detail_amplitude"]) * (1.0 + m * 2.0)
	var h := base + m * ridge * ridge * float(_p["mountain_height"]) + detail
	return clampf(h, float(bedrock_top + 8), float(WorldConst.MAX_Y - 32))


func _spline(c: float) -> float:
	var n := _spline_x.size()
	if c <= _spline_x[0]:
		return _spline_y[0]
	for i in range(1, n):
		if c <= _spline_x[i]:
			var t := (c - _spline_x[i - 1]) / (_spline_x[i] - _spline_x[i - 1])
			return lerpf(_spline_y[i - 1], _spline_y[i], t)
	return _spline_y[n - 1]


func _make_noise(salt: int, cfg: Dictionary, fractal: FastNoiseLite.FractalType) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = WorldSeed.derive(world_seed, salt)
	n.frequency = cfg["frequency"]
	n.fractal_type = fractal
	n.fractal_octaves = cfg["octaves"]
	return n
