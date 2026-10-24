class_name CaveCarver
extends RefCounted
## Пещеры (раздел 2.3): «сырные» полости, «спагетти»-тоннели, узкая «лапша», разломы,
## подземные озёра и реки (водоносные области), лава ниже lava_level.
##
## Трёхмерный шум считается на грубой сетке 4×8×4 и интерполируется трилинейно. Ячейка, во всех
## восьми углах которой пещеры нет, пропускается целиком: интерполяция не опускается ниже
## минимума углов. Так GDScript обходит лишь ~10–20% объёма колонны.

const CX := 4
const CY := 8

# Не храним ссылку на генератор: он держит нас, и цикл не дал бы освободить память.
var _seed: int
var _bedrock_top: int
var _sea_level: int
var _cfg: Dictionary
var _factor := 1.0
var _n_cheese: FastNoiseLite
var _n_s1: FastNoiseLite
var _n_s2: FastNoiseLite
var _n_n1: FastNoiseLite
var _n_ravine: FastNoiseLite
var _n_region: FastNoiseLite
var _n_aquifer: FastNoiseLite
var _b_lava: int
var _b_water: int
var _lava_level: int


func _init(gen: TerrainGenerator, cfg: Dictionary) -> void:
	_seed = gen.world_seed
	_bedrock_top = gen.bedrock_top
	_sea_level = gen.sea_level
	_cfg = cfg
	_factor = gen.settings.caves
	var s := gen.world_seed
	_n_cheese = _noise(s, 20, cfg["cheese"])
	_n_s1 = _noise(s, 21, cfg["spaghetti"])
	_n_s2 = _noise(s, 22, cfg["spaghetti"])
	_n_n1 = _noise(s, 23, cfg["noodle"])
	_n_ravine = _noise(s, 25, cfg["ravine"])
	_n_region = _noise(s, 26, { "frequency": float(cfg["ravine"]["frequency"]) * 0.25, "octaves": 1 })
	_n_aquifer = _noise(s, 27, cfg["aquifer"])
	_b_lava = gen.registry.block_num(cfg["lava_block"])
	_b_water = gen.registry.block_num(cfg["water_block"])
	_lava_level = cfg["lava_level"]


func carve(col: ChunkColumn, ctx: TerrainGenerator.Context) -> void:
	if _factor <= 0.0:
		return
	var x0 := ctx.x0
	var z0 := ctx.z0
	var bottom := _bedrock_top + 1
	var max_h := bottom
	for lz in 16:
		for lx in 16:
			max_h = maxi(max_h, TerrainGenerator.ctx_height(ctx, lx, lz))
	var y_lo := WorldConst.floor_div(bottom, CY) * CY
	var ny := (WorldConst.floor_div(mini(max_h + 2, WorldConst.MAX_Y - 1), CY) * CY - y_lo) / CY + 2

	# Водоносные горизонты: уровень воды в пещерах по столбу (NO_WATER — сухо).
	var aq := PackedInt32Array()
	aq.resize(256)
	var aq_min: int = _cfg["aquifer_level"]["min"]
	var aq_max: int = _cfg["aquifer_level"]["max"]
	for lz in 16:
		for lx in 16:
			var v := _n_aquifer.get_noise_2d(x0 + lx, z0 + lz)
			if v > float(_cfg["aquifer_threshold"]):
				var t := (_n_aquifer.get_noise_2d((x0 + lx) * 0.3 + 9000, (z0 + lz) * 0.3) + 1.0) * 0.5
				aq[lx + lz * 16] = aq_min + roundi(t * (aq_max - aq_min))
			else:
				aq[lx + lz * 16] = TerrainGenerator.NO_WATER

	# Поля «расстояния до пещеры» в узлах сетки: < 0 — пещера.
	var thr := 1.0 - (1.0 - float(_cfg["cheese_threshold"])) * _factor
	var ws := float(_cfg["spaghetti_width"]) * _factor
	var wn := float(_cfg["noodle_width"]) * _factor
	var dc := PackedFloat32Array()
	var dt := PackedFloat32Array()
	dc.resize(25 * ny)
	dt.resize(25 * ny)
	var sea := float(_sea_level)
	for iy in ny:
		var y := float(y_lo + iy * CY)
		# Ближе к поверхности больших полостей меньше, в глубине — больше.
		var t_eff := thr + 0.12 * clampf((y - (sea - 30.0)) / 60.0, 0.0, 1.0) - 0.05 * clampf((-120.0 - y) / 80.0, 0.0, 1.0)
		for iz in 5:
			for ix in 5:
				var x := float(x0 + ix * CX)
				var z := float(z0 + iz * CX)
				var i := ix + iz * 5 + iy * 25
				dc[i] = t_eff - _n_cheese.get_noise_3d(x, y * 1.8, z)
				var s2 := absf(_n_s2.get_noise_3d(x, y * 1.3, z))
				var sp := maxf(absf(_n_s1.get_noise_3d(x, y * 1.3, z)), s2) - ws
				# «Лапша» — пересечение своего шума с одним из шумов «спагетти»: на шум меньше.
				var nd := maxf(absf(_n_n1.get_noise_3d(x, y, z)), s2 * 0.6) - wn
				dt[i] = minf(sp, nd)

	for iy in ny - 1:
		for iz in 4:
			for ix in 4:
				var i000 := ix + iz * 5 + iy * 25
				var corners := [i000, i000 + 1, i000 + 5, i000 + 6, i000 + 25, i000 + 26, i000 + 30, i000 + 31]
				var min_c := INF
				var min_t := INF
				for ci: int in corners:
					min_c = minf(min_c, dc[ci])
					min_t = minf(min_t, dt[ci])
				if min_c >= 0.0 and min_t >= 0.0:
					continue
				_carve_cell(col, ctx, aq, dc, dt, i000, ix, iy, iz, y_lo)

	_carve_ravines(col, ctx, aq)


func _carve_cell(col: ChunkColumn, ctx: TerrainGenerator.Context, aq: PackedInt32Array, dc: PackedFloat32Array,
		dt: PackedFloat32Array, i000: int, ix: int, iy: int, iz: int, y_lo: int) -> void:
	var c000 := dc[i000]
	var c100 := dc[i000 + 1]
	var c010 := dc[i000 + 5]
	var c110 := dc[i000 + 6]
	var c001 := dc[i000 + 25]
	var c101 := dc[i000 + 26]
	var c011 := dc[i000 + 30]
	var c111 := dc[i000 + 31]
	var t000 := dt[i000]
	var t100 := dt[i000 + 1]
	var t010 := dt[i000 + 5]
	var t110 := dt[i000 + 6]
	var t001 := dt[i000 + 25]
	var t101 := dt[i000 + 26]
	var t011 := dt[i000 + 30]
	var t111 := dt[i000 + 31]
	var bottom := _bedrock_top
	var y_base := y_lo + iy * CY
	# Ячейка 4×8×4 выровнена по 8 и не пересекает границу секции (секции — по 16).
	var si := WorldConst.section_index(y_base)
	var sec: ChunkSection = null
	var ly_base := (y_base & 15) << 8
	for lzz in CX:
		var fz := lzz / float(CX)
		var lz := iz * CX + lzz
		for lxx in CX:
			var fx := lxx / float(CX)
			# Билинейно по x/z на нижней и верхней грани ячейки.
			var cb := lerpf(lerpf(c000, c100, fx), lerpf(c010, c110, fx), fz)
			var ct := lerpf(lerpf(c001, c101, fx), lerpf(c011, c111, fx), fz)
			var tb := lerpf(lerpf(t000, t100, fx), lerpf(t010, t110, fx), fz)
			var tt := lerpf(lerpf(t001, t101, fx), lerpf(t011, t111, fx), fz)
			# Вдоль Y значения линейны: если оба конца ≥ 0, пещеры в столбике нет.
			if minf(cb, ct) >= 0.0 and minf(tb, tt) >= 0.0:
				continue
			var lx := ix * CX + lxx
			var h := TerrainGenerator.ctx_height(ctx, lx, lz)
			var wl := TerrainGenerator.ctx_water(ctx, lx, lz)
			var wet := wl != TerrainGenerator.NO_WATER and h < wl
			var aql := aq[lx + lz * 16]
			var col_idx := lx | (lz << 4)
			for lyy in CY:
				var y := y_base + lyy
				if y <= bottom:
					continue
				if wet and y > h - 8:
					break
				var fy := lyy / float(CY)
				var cave := false
				if y < h - 4 and lerpf(cb, ct, fy) < 0.0:
					cave = true
				elif (y < h - 2 or (not wet and y <= h + 1)) and lerpf(tb, tt, fy) < 0.0:
					cave = true
				if not cave:
					continue
				var fill := 0
				if y <= _lava_level:
					fill = _b_lava
				elif aql != TerrainGenerator.NO_WATER and y <= aql:
					fill = _b_water
				if sec == null:
					sec = col.sections[si]
					if sec == null:
						sec = ChunkSection.new()
						col.sections[si] = sec
					sec.ensure_array()
					sec.all_opaque = false
				sec.blocks[col_idx | ly_base | (lyy << 8)] = fill


func _carve_ravines(col: ChunkColumn, ctx: TerrainGenerator.Context, aq: PackedInt32Array) -> void:
	var rw := float(_cfg["ravine_width"]) * _factor
	var depth: int = _cfg["ravine_depth"]
	var region := float(_cfg["ravine_region"])
	for lz in 16:
		for lx in 16:
			var x := ctx.x0 + lx
			var z := ctx.z0 + lz
			if _n_region.get_noise_2d(x, z) < region:
				continue
			var v := absf(_n_ravine.get_noise_2d(x, z))
			if v >= rw:
				continue
			var h := TerrainGenerator.ctx_height(ctx, lx, lz)
			var wl := TerrainGenerator.ctx_water(ctx, lx, lz)
			if wl != TerrainGenerator.NO_WATER and h < wl + 2:
				continue
			var d := float(depth) * (0.6 + 0.4 * GenRandom.unit2(_seed, x >> 5, z >> 5, 70))
			var aql := aq[lx + lz * 16]
			for y in range(h, maxi(h - int(d), _bedrock_top + 1), -1):
				if v >= rw * (1.0 - 0.75 * float(h - y) / d):
					break
				var fill := 0
				if y <= _lava_level:
					fill = _b_lava
				elif aql != TerrainGenerator.NO_WATER and y <= aql:
					fill = _b_water
				_put(col, lx, y, lz, fill)


func _put(col: ChunkColumn, lx: int, y: int, lz: int, block: int) -> void:
	var si := WorldConst.section_index(y)
	var s := col.sections[si]
	if s == null:
		if block == 0:
			return
		s = ChunkSection.new()
		col.sections[si] = s
	if s.blocks.is_empty():
		if s.uniform == block:
			return
		s.ensure_array()
	s.blocks[lx | (lz << 4) | ((y & 15) << 8)] = block
	s.all_opaque = false


func _noise(world_seed: int, salt: int, cfg: Dictionary) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = WorldSeed.derive(world_seed, salt)
	n.frequency = cfg["frequency"]
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = cfg["octaves"]
	return n
