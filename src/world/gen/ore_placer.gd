class_name OrePlacer
extends RefCounted
## Залежи из data/ores.json (раздел 2.5): гнёзда, жилы, пласты, жеоды, трубки, россыпи.
##
## Залежь целиком задаётся хэшем (сид, колонна-хозяйка, вид, номер) — колонна перебирает залежи
## своих и 8 соседних колонн и пишет только блоки внутри себя. Залежь замещает только
## «породы-хозяева» (hosts) и учитывает геологическую провинцию и глубину.

const SHAPES: Array[StringName] = [&"blob", &"vein", &"layer", &"geode", &"pipe", &"placer"]
const BLOB := 0
const VEIN := 1
const LAYER := 2
const GEODE := 3
const PIPE := 4
const PLACER := 5

# Не храним ссылку на генератор (цикл ссылок) — только то, что нужно.
var _seed: int
var _bedrock_top: int
var _factor: float
var _registry: ContentRegistry
var _geology: GeologySampler
var _count := 0
var _block := PackedInt32Array()
var _shape := PackedByteArray()
var _hosts: Array[PackedByteArray] = []
var _y_min := PackedInt32Array()
var _y_max := PackedInt32Array()
var _per := PackedFloat32Array()
var _s_min := PackedInt32Array()
var _s_max := PackedInt32Array()
var _provinces: Array[PackedInt32Array] = []
var _biomes: Array[PackedInt32Array] = []
var _d_min := PackedInt32Array()
var _d_max := PackedInt32Array()
var _shell := PackedInt32Array()
var _incl_block := PackedInt32Array()
var _incl_chance := PackedFloat32Array()
var _incl_y := PackedInt32Array()


func _init(gen: TerrainGenerator) -> void:
	_seed = gen.world_seed
	_bedrock_top = gen.bedrock_top
	_factor = gen.settings.ores
	_registry = gen.registry
	_geology = gen.geology
	var reg := gen.registry
	for e in reg.get_entries("ores"):
		_count += 1
		_block.append(reg.block_num(e["block"]))
		_shape.append(SHAPES.find(StringName(e["shape"])))
		var hosts := PackedByteArray()
		hosts.resize(reg.block_count())
		for h: StringName in e["hosts"]:
			hosts[reg.block_num(h)] = 1
		_hosts.append(hosts)
		_y_min.append(e["y_min"])
		_y_max.append(e["y_max"])
		_per.append(e["per_column"])
		_s_min.append(e["size"]["min"])
		_s_max.append(e["size"]["max"])
		var provs := PackedInt32Array()
		for p: StringName in e["provinces"]:
			provs.append(gen.geology.ids.find(p))
		_provinces.append(provs)
		var bios := PackedInt32Array()
		for b: StringName in e["biomes"]:
			bios.append(gen.biomes.index_of(b))
		_biomes.append(bios)
		var depth: Dictionary = e.get("depth", { "min": 0, "max": 2 })
		_d_min.append(depth["min"])
		_d_max.append(depth["max"])
		_shell.append(reg.block_num(e["shell"]) if e.has("shell") else -1)
		var inc: Dictionary = e.get("inclusion", {})
		_incl_block.append(reg.block_num(inc["block"]) if not inc.is_empty() else -1)
		_incl_chance.append(inc.get("chance", 0.0))
		_incl_y.append(inc.get("y_max", 319))


func place(col: ChunkColumn, ctx: TerrainGenerator.Context) -> void:
	var factor := _factor
	if factor <= 0.0:
		return
	var w := ColumnWriter.new(col, _registry)
	var cp := col.cpos
	for o in _count:
		if _shape[o] == PLACER:
			_placer(o, ctx, w, factor)
			continue
		var expected := _per[o] * factor
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var ncx := cp.x + dx
				var ncz := cp.y + dz
				var n := int(expected)
				if GenRandom.unit2(_seed, ncx, ncz, 81 + o * 7) < expected - n:
					n += 1
				for v in n:
					_deposit(o, ncx, ncz, v, w)


func _deposit(o: int, ncx: int, ncz: int, v: int, w: ColumnWriter) -> void:
	# Центр и размер — прямо из хэша: залежи вне досягаемости отсеиваются без RNG.
	var hh := GenRandom.hash3(_seed, ncx, ncz, o * 4096 + v, 80)
	var cx := ncx * 16 + (hh & 15)
	var cz := ncz * 16 + ((hh >> 4) & 15)
	var size := _s_min[o] + int(GenRandom.unit(GenRandom.mix(hh + 1)) * (_s_max[o] - _s_min[o] + 1))
	var ext := _extent(o, size)
	if cx + ext < w.x0 or cx - ext > w.x0 + 15 or cz + ext < w.z0 or cz - ext > w.z0 + 15:
		return
	var cy := _y_min[o] + int(GenRandom.unit(GenRandom.mix(hh + 2)) * (_y_max[o] - _y_min[o] + 1))
	var rng := GenRandom.rng(GenRandom.mix(hh + 3))
	var provs := _provinces[o]
	if not provs.is_empty() and not provs.has(_geology.province_at(cx, cz)):
		return
	var hosts := _hosts[o]
	var blk := _block[o]
	match _shape[o]:
		BLOB:
			var r := maxf(1.0, pow(size * 0.75 / PI, 1.0 / 3.0))
			var rx := r * rng.randf_range(0.7, 1.3)
			var ry := r * rng.randf_range(0.6, 1.1)
			var rz := r * rng.randf_range(0.7, 1.3)
			_ellipsoid(w, cx, cy, cz, rx, ry, rz, hosts, blk, o)
		VEIN:
			var length := maxi(3, size / 2 + 1)
			var a := rng.randf() * TAU
			var dir := Vector3(cos(a), rng.randf_range(-0.5, 0.5), sin(a)).normalized()
			for s in length:
				var px := cx + roundi(dir.x * s)
				var py := cy + roundi(dir.y * s)
				var pz := cz + roundi(dir.z * s)
				_put(w, px, py, pz, hosts, blk)
				if GenRandom.unit3(_seed, px, py, pz, 82) < 0.5:
					_put(w, px, py + 1, pz, hosts, blk)
		LAYER:
			var thick := 1 + size / 40
			var r := sqrt(size / PI / thick)
			var rx := r * rng.randf_range(0.8, 1.6)
			var rz := r * rng.randf_range(0.8, 1.6)
			var tilt := rng.randf_range(-0.15, 0.15)
			for ddx in range(-ceili(rx), ceili(rx) + 1):
				for ddz in range(-ceili(rz), ceili(rz) + 1):
					var fx := ddx / rx
					var fz := ddz / rz
					if fx * fx + fz * fz > 1.0:
						continue
					var by := cy + roundi(ddx * tilt)
					for t in thick:
						_put(w, cx + ddx, by + t, cz + ddz, hosts, blk)
		GEODE:
			var r := float(size)
			var ri := ceili(r)
			for ddy in range(-ri, ri + 1):
				for ddx in range(-ri, ri + 1):
					for ddz in range(-ri, ri + 1):
						var d := sqrt(float(ddx * ddx + ddy * ddy + ddz * ddz))
						if d > r:
							continue
						var b := 0
						if d > r - 1.0:
							b = _shell[o]
						elif d > r - 2.0:
							b = blk
						_put(w, cx + ddx, cy + ddy, cz + ddz, hosts, b)
		PIPE:
			var r := float(size)
			var inc := _incl_block[o]
			for y in range(_y_min[o], _y_max[o] + 1):
				var ox := cx + roundi(sin(y * 0.05 + cx) * 2.0)
				var oz := cz + roundi(cos(y * 0.04 + cz) * 2.0)
				var ri := ceili(r)
				for ddx in range(-ri, ri + 1):
					for ddz in range(-ri, ri + 1):
						if ddx * ddx + ddz * ddz > r * r + 0.5:
							continue
						var px := ox + ddx
						var pz := oz + ddz
						if not w.inside(px, pz):
							continue
						var b := blk
						if inc >= 0 and y <= _incl_y[o] and GenRandom.unit3(_seed, px, y, pz, 83) < _incl_chance[o]:
							b = inc
						_put(w, px, y, pz, hosts, b)


## Россыпи и корки у поверхности в заданных биомах (золото в руслах, болотная руда, соль).
func _placer(o: int, ctx: TerrainGenerator.Context, w: ColumnWriter, factor: float) -> void:
	var bios := _biomes[o]
	var hosts := _hosts[o]
	var chance := _per[o] * factor
	for lz in 16:
		for lx in 16:
			if not bios.is_empty() and not bios.has(ctx.bio[lx + lz * 16]):
				continue
			var x := ctx.x0 + lx
			var z := ctx.z0 + lz
			# Пятнами: в половине участков 4×4 россыпи нет, в остальных — вдвое гуще.
			if GenRandom.unit2(_seed, x >> 2, z >> 2, 84 + o) < 0.5:
				continue
			var h := TerrainGenerator.ctx_height(ctx, lx, lz)
			for d in range(_d_min[o], _d_max[o] + 1):
				var y := h - d
				if GenRandom.unit3(_seed, x, y, z, 85 + o) < chance * 2.0:
					_put(w, x, y, z, hosts, _block[o])


func _ellipsoid(w: ColumnWriter, cx: int, cy: int, cz: int, rx: float, ry: float, rz: float,
		hosts: PackedByteArray, blk: int, o: int) -> void:
	for ddy in range(-ceili(ry), ceili(ry) + 1):
		for ddx in range(-ceili(rx), ceili(rx) + 1):
			for ddz in range(-ceili(rz), ceili(rz) + 1):
				var fx := ddx / rx
				var fy := ddy / ry
				var fz := ddz / rz
				var d := fx * fx + fy * fy + fz * fz
				if d > 1.0 or not w.inside(cx + ddx, cz + ddz):
					continue
				if d > 0.65 and d > 1.0 - GenRandom.unit3(_seed, cx + ddx, cy + ddy, cz + ddz, 86 + o) * 0.35:
					continue
				_put(w, cx + ddx, cy + ddy, cz + ddz, hosts, blk)


func _put(w: ColumnWriter, x: int, y: int, z: int, hosts: PackedByteArray, blk: int) -> void:
	if y <= _bedrock_top or y >= WorldConst.MAX_Y:
		return
	var cur := w.get_block(x, y, z)
	if cur >= 0 and hosts[cur] == 1:
		w.set_block(x, y, z, blk)


func _extent(o: int, size: int) -> int:
	match _shape[o]:
		BLOB:
			return ceili(pow(size * 0.75 / PI, 1.0 / 3.0) * 1.3) + 1
		VEIN:
			return size / 2 + 2
		LAYER:
			return ceili(sqrt(size / PI) * 1.7) + 1
		GEODE:
			return size + 1
		PIPE:
			return size + 3
	return 16

