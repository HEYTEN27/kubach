class_name TerrainGenerator
extends RefCounted
## Генератор мира (этапы 1–2). Чистая функция от (сид, настройки, координаты колонны):
## один и тот же сид даёт один и тот же мир при любом порядке генерации. Потокобезопасен —
## после создания только читает свои шумы и таблицы.
##
## Конвейер колонны:
##   1. Сетка климата с шагом 4 блока (с запасом 12 вокруг колонны): температура, влажность,
##      weirdness, категория рельефа (суша/горы/пик/берег/река/океан), биом, веса модификаторов.
##   2. Высота каждого столба: континентальность → сплайн, эрозия + хребты, детали, модификаторы
##      биомов (болото, террасы, плато, карст, дюны, ледник), реки, горные озёра.
##   3. Столб пород «прогонами»: поверхность биома, слоистые породы каньонов, осадочный чехол и
##      фундамент геологической провинции, глубинный слой, материнская порода; вода/лёд.
##   4. Пещеры (CaveCarver), руды (OrePlacer), растительность (VegetationPlacer).
##   5. Карта биомов и цвета травы/листвы с блендингом для мешера.
## Параметры — data/worldgen.json, biomes.json, geology.json, ores.json, trees.json, world_types.json.

const MAX_RUNS := 32
const GRID := 4
## Запас сетки вокруг колонны: радиус блендинга + дизеринг + охват деревьев соседей.
const MARGIN := 12
const GN := (16 + 2 * MARGIN) / GRID + 1
const NO_WATER := -100000
## Сетка цветов для мешера: 5×5 узлов (0, 4, 8, 12, 16) × 8 каналов (сезон × трава/листва).
const TINT_N := 5

var world_seed: int
var sea_level: int
var bedrock_top: int
var settings: WorldGenSettings
var registry: ContentRegistry
var biomes: BiomeSource
var trees: TreeBuilder
var geology: GeologySampler
var caves: CaveCarver
var ores: OrePlacer
var vegetation: VegetationPlacer
var flat := false

var _p: Dictionary
var _n_cont: FastNoiseLite
var _n_ero: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_detail2: FastNoiseLite
var _n_temp: FastNoiseLite
var _n_hum: FastNoiseLite
var _n_weird: FastNoiseLite
var _n_river: FastNoiseLite
var _n_karst: FastNoiseLite
var _spline_x := PackedFloat64Array()
var _spline_y := PackedFloat64Array()
var _cont_offset := 0.0
var _cont_scale := 1.0
var _mountain_scale := 1.0
var _biome_scale := 1.0
var _sea_shift := 0
var _temp_bias := 0.0
var _cliff_slope := 3
var _peak_height := 100
var _blend_cells := 2
var _river: Dictionary
var _lakes: Dictionary
var _b_bedrock: int
var _b_fluid: int
var _b_ice: int
var _soft_cats := PackedByteArray()
## Пометки блоков: растения могут расти (plantable), руда/жеода могут заменить (не используется здесь).
var plantable := PackedByteArray()


func _init(p_seed: int, p_registry: ContentRegistry, p_settings: WorldGenSettings = null) -> void:
	world_seed = p_seed
	registry = p_registry
	settings = p_settings if p_settings != null else WorldGenSettings.new()
	var wt := registry.get_entry("world_types", settings.world_type)
	if wt.is_empty():
		wt = registry.get_entry("world_types", &"normal")
	_p = registry.get_entry("worldgen", StringName(wt.get("preset", "default")))
	assert(not _p.is_empty(), "нет пресета генерации")
	flat = wt.get("flat", false)
	_cont_offset = wt.get("continental_offset", 0.0)
	_cont_scale = wt.get("continental_scale", 1.0)
	_mountain_scale = wt.get("mountain_scale", 1.0)
	_biome_scale = float(wt.get("biome_scale", 1.0)) * settings.biome_size
	sea_level = settings.sea_level
	_sea_shift = sea_level - int(_p["sea_level"])
	bedrock_top = _p["bedrock_top"]
	_temp_bias = _p["temperature_bias"]
	_cliff_slope = _p["cliff_slope"]
	_peak_height = _p["peak_height"]
	_blend_cells = clampi(roundi(float(_p["biome_blend"]) / GRID), 1, 3)
	_river = _p["rivers"]
	_lakes = _p["lakes"]

	var noise: Dictionary = _p["noise"]
	_n_cont = _make_noise(1, noise["continental"], FastNoiseLite.FRACTAL_FBM)
	_n_ero = _make_noise(2, noise["erosion"], FastNoiseLite.FRACTAL_FBM)
	_n_ridge = _make_noise(3, noise["ridges"], FastNoiseLite.FRACTAL_RIDGED)
	_n_detail = _make_noise(4, noise["detail"], FastNoiseLite.FRACTAL_FBM)
	_n_detail2 = _make_noise(6, noise["detail"], FastNoiseLite.FRACTAL_FBM)
	_n_temp = _make_noise(7, noise["temperature"], FastNoiseLite.FRACTAL_FBM)
	_n_hum = _make_noise(8, noise["humidity"], FastNoiseLite.FRACTAL_FBM)
	_n_weird = _make_noise(9, noise["weirdness"], FastNoiseLite.FRACTAL_FBM)
	_n_river = _make_noise(10, noise["river"], FastNoiseLite.FRACTAL_FBM)
	_n_karst = FastNoiseLite.new()
	_n_karst.noise_type = FastNoiseLite.TYPE_CELLULAR
	_n_karst.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_n_karst.seed = WorldSeed.derive(world_seed, 11)
	_n_karst.frequency = 0.03
	for pt: Dictionary in _p["height_spline"]:
		_spline_x.append(pt["x"])
		_spline_y.append(pt["y"])

	_b_bedrock = registry.block_num(_p["bedrock_block"])
	_b_fluid = registry.block_num(_p["fluid"])
	_b_ice = registry.block_num(_p["ice"])
	for n in registry.block_count():
		var def := registry.block_by_num(n)
		plantable.append(1 if def.has_tag("plantable") else 0)

	trees = TreeBuilder.new(registry, world_seed)
	biomes = BiomeSource.new(registry, trees.index)
	for c in BiomeSource.CATEGORIES.size():
		var any := 0
		for i in biomes.count:
			if biomes.category[i] == c and biomes.kind[i] != 0:
				any = 1
		_soft_cats.append(any)
	geology = GeologySampler.new(registry, world_seed, noise["province"], noise["strata"])
	caves = CaveCarver.new(self, _p["caves"])
	ores = OrePlacer.new(self)
	vegetation = VegetationPlacer.new(self)


# ---------------------------------------------------------------------------------------------
# Публичный API

func generate_column(cpos: Vector2i) -> ChunkColumn:
	var ctx := make_context(cpos)
	var col := ChunkColumn.new(cpos)
	_compute_surface(ctx)
	col.surface_min = ctx_surface_min(ctx)
	_fill_column(col, ctx)
	if not flat:
		caves.carve(col, ctx)
	ores.place(col, ctx)
	vegetation.place(self, col, ctx)
	_apply_climate(col, ctx)
	_finalize_sections(col)
	return col


## Для колонны из сохранения: карта биомов и цвета (их не храним на диске).
func fill_climate(col: ChunkColumn) -> void:
	var ctx := make_context(col.cpos)
	_compute_surface(ctx)
	col.surface_min = ctx_surface_min(ctx)
	_apply_climate(col, ctx)
	_finalize_sections(col, true)


## Высота поверхности (Y верхнего твёрдого блока рельефа) в точке.
func surface_height(x: int, z: int) -> int:
	return surface_info(x, z)[0]


## [высота, уровень воды (NO_WATER — сухо), индекс биома].
func surface_info(x: int, z: int) -> PackedInt32Array:
	var ctx := make_context(Vector2i(x >> 4, z >> 4), false)
	var r := height_at(ctx, x, z)
	return PackedInt32Array([r.x, r.y, biome_at(ctx, x, z)])


## Биом в точке (индекс BiomeSource) — с дизерингом границ.
func biome_index_at(x: int, z: int) -> int:
	return biome_at(make_context(Vector2i(x >> 4, z >> 4), false), x, z)


## Биом узла климатической сетки без дизеринга (быстро — для предпросмотра карты).
func grid_biome(x: int, z: int) -> int:
	return _grid_point(x, z, false)[0]


## Для предпросмотра: Vector2(биом, базовая высота).
func preview_sample(x: int, z: int) -> Vector2:
	var g := _grid_point(x, z, false)
	return Vector2(g[0], g[3])


## Высота базового рельефа без модификаторов (быстро — для предпросмотра карты).
func base_height(x: int, z: int) -> float:
	return _base(float(x), float(z)).x


# ---------------------------------------------------------------------------------------------
# Контекст колонны: сетка климата и данные по столбам

class Context:
	var cpos: Vector2i
	var x0: int
	var z0: int
	var gx0: int
	var gz0: int
	## Полная сетка GN×GN посчитана (иначе узлы считаются по запросу и кэшируются).
	var full := false
	var biome := PackedInt32Array()
	var cat := PackedByteArray()
	var kinds := PackedFloat32Array()
	var have := PackedByteArray()
	var lakes: Array = []
	## По столбам 18×18 (с краем 1 для крутизны): высота и уровень воды.
	var heights := PackedInt32Array()
	var wls := PackedInt32Array()
	## По столбам 16×16: биом и верхний блок.
	var bio := PackedInt32Array()
	var tops := PackedInt32Array()


func make_context(cpos: Vector2i, full: bool = true) -> Context:
	var ctx := Context.new()
	ctx.cpos = cpos
	ctx.x0 = cpos.x * 16
	ctx.z0 = cpos.y * 16
	ctx.gx0 = ctx.x0 - MARGIN
	ctx.gz0 = ctx.z0 - MARGIN
	ctx.biome.resize(GN * GN)
	ctx.cat.resize(GN * GN)
	ctx.kinds.resize(GN * GN * BiomeSource.KIND_COUNT)
	ctx.have.resize(GN * GN)
	if full:
		for gz in GN:
			for gx in GN:
				_ensure_grid(ctx, gx, gz)
		ctx.full = true
	ctx.lakes = _lakes_near(ctx.x0 - MARGIN - 24, ctx.z0 - MARGIN - 24, ctx.x0 + 16 + MARGIN + 24, ctx.z0 + 16 + MARGIN + 24)
	return ctx


func _ensure_grid(ctx: Context, gx: int, gz: int) -> int:
	var i := gx + gz * GN
	if ctx.have[i] == 0:
		var g := _grid_point(ctx.gx0 + gx * GRID, ctx.gz0 + gz * GRID)
		ctx.biome[i] = g[0]
		ctx.cat[i] = g[1]
		var k: PackedFloat32Array = g[2]
		for j in BiomeSource.KIND_COUNT:
			ctx.kinds[i * BiomeSource.KIND_COUNT + j] = k[j]
		ctx.have[i] = 1
	return i


## Узел сетки: [биом, категория, веса модификаторов, базовая высота].
func _grid_point(x: int, z: int, with_kinds: bool = true) -> Array:
	var fx := float(x)
	var fz := float(z)
	var base := _base(fx, fz)
	var hb := base.x
	var bs := _biome_scale
	var t := _n_temp.get_noise_2d(fx / bs, fz / bs) + _temp_bias
	t -= clampf((hb - sea_level - 30.0) / 250.0, 0.0, 0.35)
	var hum := _n_hum.get_noise_2d(fx / bs, fz / bs)
	var w := _n_weird.get_noise_2d(fx / bs, fz / bs)
	var cat := BiomeSource.CAT_LAND
	if not flat:
		var ch := _river_channel(fx, fz, hb)
		if ch > 0.5 and hb > sea_level - 3:
			cat = BiomeSource.CAT_RIVER
		elif hb < sea_level - 1:
			cat = BiomeSource.CAT_OCEAN
		elif hb <= sea_level + 3 and base.y < -0.02:
			cat = BiomeSource.CAT_BEACH
		elif hb > sea_level + _peak_height:
			cat = BiomeSource.CAT_PEAK
		elif base.z > 0.45:
			cat = BiomeSource.CAT_MOUNTAIN
	if not biomes.has_category(cat):
		cat = BiomeSource.CAT_LAND
	var e := (hb - sea_level) / 64.0
	var b := biomes.pick(cat, t, hum, w, e)
	var kinds := PackedFloat32Array()
	kinds.resize(BiomeSource.KIND_COUNT)
	if with_kinds and _soft_cats[cat] == 1 and not flat:
		biomes.soft_kinds(cat, t, hum, w, e, kinds, 0)
	return [b, cat, kinds, hb]


## Биом блока: ближайший узел сетки после случайного сдвига ±3 — границы «перемешаны».
func biome_at(ctx: Context, x: int, z: int) -> int:
	var jx := int(GenRandom.unit2(world_seed, x, z, 31) * 7.0) - 3
	var jz := int(GenRandom.unit2(world_seed, x, z, 32) * 7.0) - 3
	var gx := clampi(roundi(float(x + jx - ctx.gx0) / GRID), 0, GN - 1)
	var gz := clampi(roundi(float(z + jz - ctx.gz0) / GRID), 0, GN - 1)
	return ctx.biome[_ensure_grid(ctx, gx, gz)]


## Веса модификаторов в точке — билинейно по сетке.
func _kinds_at(ctx: Context, x: int, z: int, out: PackedFloat32Array) -> void:
	var fx := clampf(float(x - ctx.gx0) / GRID, 0.0, GN - 1.001)
	var fz := clampf(float(z - ctx.gz0) / GRID, 0.0, GN - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i00 := _ensure_grid(ctx, ix, iz) * BiomeSource.KIND_COUNT
	var i10 := _ensure_grid(ctx, ix + 1, iz) * BiomeSource.KIND_COUNT
	var i01 := _ensure_grid(ctx, ix, iz + 1) * BiomeSource.KIND_COUNT
	var i11 := _ensure_grid(ctx, ix + 1, iz + 1) * BiomeSource.KIND_COUNT
	for k in BiomeSource.KIND_COUNT:
		var a := lerpf(ctx.kinds[i00 + k], ctx.kinds[i10 + k], tx)
		var b := lerpf(ctx.kinds[i01 + k], ctx.kinds[i11 + k], tx)
		out[k] = lerpf(a, b, tz)


# ---------------------------------------------------------------------------------------------
# Рельеф

## (высота, континентальность, горность).
func _base(x: float, z: float) -> Vector3:
	if flat:
		return Vector3(sea_level + 1, 0.2, 0.0)
	var c := _n_cont.get_noise_2d(x * _cont_scale, z * _cont_scale) + _cont_offset
	var base := _spline(c) + _sea_shift
	var me: Dictionary = _p["mountain_erosion"]
	var m := smoothstep(float(me["start"]), float(me["full"]), _n_ero.get_noise_2d(x, z))
	m *= smoothstep(-0.12, 0.05, c) * _mountain_scale
	var ridge := (_n_ridge.get_noise_2d(x, z) + 1.0) * 0.5
	var detail := _n_detail.get_noise_2d(x, z) * float(_p["detail_amplitude"]) * (1.0 + minf(m, 1.0) * 2.0)
	var h := base + m * ridge * ridge * float(_p["mountain_height"]) + detail
	return Vector3(clampf(h, float(bedrock_top + 12), float(WorldConst.MAX_Y - 24)), c, m)


func _river_channel(x: float, z: float, hb: float) -> float:
	var rv := absf(_n_river.get_noise_2d(x, z))
	var w := float(_river["width"])
	return (1.0 - smoothstep(w * 0.6, w, rv)) * _river_fade(hb)


func _river_fade(hb: float) -> float:
	var mh := float(_river["max_height"])
	return (1.0 - smoothstep(sea_level + mh * 0.6, sea_level + mh, hb)) * smoothstep(sea_level - 6.0, sea_level - 2.0, hb)


## Итоговая высота и уровень воды столба: Vector2i(h, wl).
func height_at(ctx: Context, x: int, z: int, k: PackedFloat32Array = PackedFloat32Array()) -> Vector2i:
	var fx := float(x)
	var fz := float(z)
	var base := _base(fx, fz)
	var h := base.x
	if flat:
		return Vector2i(floori(h), NO_WATER)
	if k.size() != BiomeSource.KIND_COUNT:
		k = PackedFloat32Array()
		k.resize(BiomeSource.KIND_COUNT)
	_kinds_at(ctx, x, z, k)
	var sea := float(sea_level)
	if k[1] > 0.001:  # болото: почти уровень моря, лужи и кочки
		h = lerpf(h, sea + _n_detail2.get_noise_2d(fx, fz) * 1.8 - 0.2, minf(k[1], 1.0))
	if k[2] > 0.001:  # каньоны: поднятое плато со ступенями
		var raised := maxf(h, sea + 16.0 + (_n_ridge.get_noise_2d(fz, fx) + 1.0) * 14.0)
		var step := 6.0
		var f := raised / step
		var terr := floorf(f) * step + smoothstep(0.7, 1.0, f - floorf(f)) * step
		h = lerpf(h, terr, k[2])
	if k[3] > 0.001:  # вулканическое плато
		h = lerpf(h, sea + 24.0 + _n_detail.get_noise_2d(fx, fz) * 1.5, k[3])
	if k[4] > 0.001:  # карстовые воронки
		var d := (_n_karst.get_noise_2d(fx, fz) + 1.0) * 0.5
		if d < 0.2:
			h -= k[4] * 13.0 * (1.0 - d / 0.2) * (1.0 - d / 0.2)
	if k[5] > 0.001:  # дюны
		var dune := absf(sin(fx * 0.07 + _n_detail.get_noise_2d(fx, fz) * 2.5)) * 7.0
		h = lerpf(h, sea + 4.0 + dune, k[5] * 0.85)
	if k[6] > 0.001:  # ледник
		h += k[6] * 8.0
	if k[7] > 0.001:  # изрезанный рельеф
		h += k[7] * absf(_n_detail2.get_noise_2d(fx, fz)) * 9.0
	# Реки: долина и русло ниже уровня моря.
	var rv := absf(_n_river.get_noise_2d(fx, fz))
	var fade := _river_fade(base.x)
	if fade > 0.0:
		var w := float(_river["width"])
		var valley := (1.0 - smoothstep(w, float(_river["valley"]), rv)) * fade
		var channel := (1.0 - smoothstep(w * 0.6, w, rv)) * fade
		h = lerpf(h, minf(h, sea + 2.0 + (h - sea) * 0.35), valley)
		h = lerpf(h, sea - float(_river["depth"]), channel)
	var wl := sea_level if h < sea else NO_WATER
	# Горные озёра со своим уровнем воды.
	for lake: Array in ctx.lakes:
		var dx: float = fx - float(lake[0])
		var dz: float = fz - float(lake[1])
		var r: float = lake[2]
		var d2: float = dx * dx + dz * dz
		if d2 < r * r:
			var level: int = lake[3]
			var bowl: float = float(lake[4]) * (1.0 - d2 / (r * r))
			h = minf(h, level - 0.5 - bowl)
			wl = maxi(wl, level)
	return Vector2i(floori(h), wl)


## Озёра, задевающие прямоугольник. Озеро — [cx, cz, радиус, уровень, глубина].
func _lakes_near(xa: int, za: int, xb: int, zb: int) -> Array:
	var out := []
	if flat or float(_lakes["chance"]) <= 0.0:
		return out
	var cell: int = _lakes["cell"]
	for ci in range(WorldConst.floor_div(xa, cell), WorldConst.floor_div(xb, cell) + 1):
		for cj in range(WorldConst.floor_div(za, cell), WorldConst.floor_div(zb, cell) + 1):
			var lake := _lake_in_cell(ci, cj)
			if not lake.is_empty():
				out.append(lake)
	return out


func _lake_in_cell(ci: int, cj: int) -> Array:
	if GenRandom.unit2(world_seed, ci, cj, 50) >= float(_lakes["chance"]):
		return []
	var cell: int = _lakes["cell"]
	var cx := ci * cell + 40 + int(GenRandom.unit2(world_seed, ci, cj, 51) * (cell - 80))
	var cz := cj * cell + 40 + int(GenRandom.unit2(world_seed, ci, cj, 52) * (cell - 80))
	var rmin: int = _lakes["radius"]["min"]
	var rmax: int = _lakes["radius"]["max"]
	var r := rmin + GenRandom.unit2(world_seed, ci, cj, 53) * (rmax - rmin)
	var hb := _base(cx, cz).x
	var level := floori(hb) - 1
	if level <= sea_level + 2 or level > sea_level + int(_lakes["max_height"]):
		return []
	if _river_channel(cx, cz, hb) > 0.05:
		return []
	# Берег должен быть выше воды по всему кругу, иначе вода «повиснет».
	for i in 8:
		var a := TAU * i / 8.0
		if _base(cx + cos(a) * r * 1.15, cz + sin(a) * r * 1.15).x < level + 1.0:
			return []
	return [float(cx), float(cz), r, level, int(_lakes["depth"])]


func _compute_surface(ctx: Context) -> void:
	ctx.heights.resize(324)
	ctx.wls.resize(324)
	var k := PackedFloat32Array()
	k.resize(BiomeSource.KIND_COUNT)
	for hz in 18:
		for hx in 18:
			var r := height_at(ctx, ctx.x0 + hx - 1, ctx.z0 + hz - 1, k)
			ctx.heights[hx + hz * 18] = r.x
			ctx.wls[hx + hz * 18] = r.y
	ctx.bio.resize(256)
	ctx.tops.resize(256)
	for lz in 16:
		for lx in 16:
			ctx.bio[lx + lz * 16] = biome_at(ctx, ctx.x0 + lx, ctx.z0 + lz)


## Минимум высоты поверхности по колонне (без краёв).
static func ctx_surface_min(ctx: Context) -> int:
	var m := WorldConst.MAX_Y
	for lz in 16:
		for lx in 16:
			m = mini(m, ctx.heights[(lx + 1) + (lz + 1) * 18])
	return m


## Высота и вода столба колонны по локальным координатам.
static func ctx_height(ctx: Context, lx: int, lz: int) -> int:
	return ctx.heights[(lx + 1) + (lz + 1) * 18]


static func ctx_water(ctx: Context, lx: int, lz: int) -> int:
	return ctx.wls[(lx + 1) + (lz + 1) * 18]


# ---------------------------------------------------------------------------------------------
# Столб пород

func _fill_column(col: ChunkColumn, ctx: Context) -> void:
	var tops := PackedInt32Array()
	var blks := PackedInt32Array()
	tops.resize(256 * MAX_RUNS)
	blks.resize(256 * MAX_RUNS)
	var seg_top := PackedInt32Array()
	var seg_blk := PackedInt32Array()
	seg_top.resize(MAX_RUNS)
	seg_blk.resize(MAX_RUNS)
	for lz in 16:
		for lx in 16:
			var i := lx + lz * 16
			var hi := (lx + 1) + (lz + 1) * 18
			var h := ctx.heights[hi]
			var wl := ctx.wls[hi]
			var b := ctx.bio[i]
			var x := ctx.x0 + lx
			var z := ctx.z0 + lz
			var slope := maxi(maxi(absi(h - ctx.heights[hi - 1]), absi(h - ctx.heights[hi + 1])),
				maxi(absi(h - ctx.heights[hi - 18]), absi(h - ctx.heights[hi + 18])))
			var top := biomes.top[b]
			var soil := biomes.soil[b]
			var sd := biomes.soil_depth[b]
			var sub := biomes.subsoil[b]
			var subd := biomes.subsoil_depth[b]
			if wl != NO_WATER and h < wl:
				top = biomes.underwater[b]
				soil = top
				sd = 3
				sub = -1
			elif slope >= _cliff_slope:
				var cl := biomes.cliff[b]
				if cl >= 0:
					top = cl
					soil = cl
					sd = 2
					sub = -1
				elif slope >= _cliff_slope + 3:
					sd = 0
					top = -2  # голый камень: верх возьмёт первый слой геологии
			ctx.tops[i] = top

			# Сегменты сверху вниз: (верхняя Y, блок).
			var n := 0
			var y := h
			var prov := geology.province_at(x, z)
			if top == -2:
				var l: Array = geology.layers[prov]
				top = (l[0] as PackedInt32Array)[0]
				ctx.tops[i] = top
			seg_top[n] = y
			seg_blk[n] = top
			n += 1
			y -= 1
			if sd > 0:
				seg_top[n] = y
				seg_blk[n] = soil
				n += 1
				y -= sd
			if sub >= 0 and subd > 0:
				seg_top[n] = y
				seg_blk[n] = sub
				n += 1
				y -= subd
			# Слоистые породы каньонов: по абсолютной высоте, на 40 блоков вглубь.
			var band: Array = biomes.bands[b]
			var bb: PackedInt32Array = band[0]
			if not bb.is_empty():
				var bt: PackedInt32Array = band[1]
				var period := 0
				for t in bt:
					period += t
				var stop := y - 40
				while y > stop and n < MAX_RUNS - 12:
					var phase := posmod(y, period)
					var acc := 0
					var k := 0
					while k < bt.size() and acc + bt[k] <= phase:
						acc += bt[k]
						k += 1
					seg_top[n] = y
					seg_blk[n] = bb[k]
					n += 1
					y -= phase - acc + 1
			# Геология: чехол и фундамент до глубинного слоя.
			var l: Array = geology.layers[prov]
			var lb: PackedInt32Array = l[0]
			var deep_top := geology.deep_top_at(prov, x, z)
			for j in lb.size():
				if y <= deep_top or n >= MAX_RUNS - 4:
					break
				var th := geology.thickness(prov, j, x, z) if j < lb.size() - 1 else 10000
				if th <= 0:
					continue
				seg_top[n] = y
				seg_blk[n] = lb[j]
				n += 1
				y = maxi(y - th, deep_top)
			if y > deep_top:
				y = deep_top
			if y > bedrock_top:
				seg_top[n] = y
				seg_blk[n] = geology.deep_block[prov]
				n += 1
			seg_top[n] = bedrock_top
			seg_blk[n] = _b_bedrock
			n += 1

			# Прогоны снизу вверх: сегменты в обратном порядке (без пустых), затем вода и воздух.
			var c := i * MAX_RUNS
			var m := 0
			var prev := WorldConst.MIN_Y - 1
			for s in range(n - 1, -1, -1):
				var t := seg_top[s]
				if t <= prev:
					continue
				tops[c + m] = t
				blks[c + m] = seg_blk[s]
				m += 1
				prev = t
			if wl != NO_WATER and wl > h:
				var freeze := biomes.freeze_water[b] == 1
				var water_top := wl - 1 if freeze else wl
				if water_top > prev:
					tops[c + m] = mini(water_top, WorldConst.MAX_Y - 1)
					blks[c + m] = _b_fluid
					m += 1
					prev = water_top
				if freeze and wl > prev:
					tops[c + m] = wl
					blks[c + m] = _b_ice
					m += 1
					prev = wl
			tops[c + m] = WorldConst.MAX_Y - 1
			blks[c + m] = 0
	_fill_sections(col, tops, blks)


func _fill_sections(col: ChunkColumn, tops: PackedInt32Array, blks: PackedInt32Array) -> void:
	var count := WorldConst.SECTIONS_PER_COLUMN
	var sec_block := PackedInt32Array()
	sec_block.resize(count)
	var mixed := PackedByteArray()
	mixed.resize(count)
	# Секция однородна, если внутри неё нет границы прогона и на её нижней Y во всех столбах
	# один и тот же блок.
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
		var y1 := y0 + 15
		var arr := PackedInt32Array()
		arr.resize(WorldConst.SECTION_VOLUME)
		# Заливаем преобладающим блоком (по середине секции у первого столба), потом пишем
		# только отличающиеся отрезки прогонов — обычно это малая часть объёма.
		var r0 := 0
		while tops[r0] < y0 + 8:
			r0 += 1
		var major := blks[r0]
		arr.fill(major)
		var all_opaque := registry.block_opaque[major] == 1
		var opaque := registry.block_opaque
		for c in 256:
			var base := c * MAX_RUNS
			var r := 0
			while tops[base + r] < y0:
				r += 1
			var lo := y0
			while lo <= y1:
				var t := mini(tops[base + r], y1)
				var b := blks[base + r]
				if b != major:
					if opaque[b] != 1:
						all_opaque = false
					# c = lx + lz*16, а индекс в секции = lx | lz<<4 | ly<<8.
					for y in range(lo, t + 1):
						arr[c | ((y - y0) << 8)] = b
				lo = t + 1
				r += 1
		var s := ChunkSection.new()
		s.blocks = arr
		s.all_opaque = all_opaque
		col.sections[si] = s


## Сжатие однородных секций. Флаги all_opaque/has_special уже выставлены при записи
## (заливка, ColumnWriter, пещеры); full_analyze — пересчитать заново (колонны из сохранения).
func _finalize_sections(col: ChunkColumn, full_analyze: bool = false) -> void:
	for si in col.sections.size():
		var s := col.sections[si]
		if s == null:
			continue
		if s.try_compact():
			if s.uniform == 0:
				col.sections[si] = null
				continue
			s.analyze(registry.block_opaque, registry.block_shape)
		elif full_analyze:
			s.analyze(registry.block_opaque, registry.block_shape)


# ---------------------------------------------------------------------------------------------
# Климат колонны для мешера

func _apply_climate(col: ChunkColumn, ctx: Context) -> void:
	if ctx.bio.size() != 256:
		ctx.bio.resize(256)
		for lz in 16:
			for lx in 16:
				ctx.bio[lx + lz * 16] = biome_at(ctx, ctx.x0 + lx, ctx.z0 + lz)
	col.biomes = PackedByteArray()
	col.biomes.resize(256)
	for i in 256:
		col.biomes[i] = ctx.bio[i]
	# Размытые цвета: для каждого из 5×5 узлов внутри колонны — среднее по квадрату ±_blend_cells.
	var tints := PackedColorArray()
	tints.resize(8 * TINT_N * TINT_N)
	var first := MARGIN / GRID
	var r := _blend_cells
	var cnt := float((2 * r + 1) * (2 * r + 1))
	for tz in TINT_N:
		for tx in TINT_N:
			# Сколько раз каждый биом встречается в окне — обычно 1–3 разных.
			var seen := {}
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var bi := ctx.biome[_ensure_grid(ctx, first + tx + dx, first + tz + dz)]
					seen[bi] = seen.get(bi, 0) + 1
			for ch in 8:
				var acc := Color(0, 0, 0, 0)
				for bi: int in seen:
					acc += biomes.palettes[bi * 8 + ch] * (seen[bi] / cnt)
				tints[ch * TINT_N * TINT_N + tz * TINT_N + tx] = acc
	col.tints = tints


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
