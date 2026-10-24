class_name VegetationPlacer
extends RefCounted
## Растительность и особенности ландшафта по биомам: травы, цветы, ягоды, грибы, кувшинки,
## деревья, валежник, курумники, кочки, валуны, гейзеры, кораллы, снежный покров.
##
## Деревья и крупные объекты могут пересекать границу колонны: колонна перебирает кандидатов
## своих и 8 соседних колонн. Решение «расти или нет» принимается только по чистым функциям
## генератора (биом, высота), а не по уже записанным блокам — поэтому обе колонны на стыке
## приходят к одному и тому же дереву.

const TREE_ATTEMPTS := 10
const MAX_TREE_DENSITY := 10.0
const FEATURE_ATTEMPTS := 8

# Генератор передаётся параметром: хранить ссылку нельзя (он держит нас — цикл ссылок).
var _seed: int
var _registry: ContentRegistry
var _b_fluid: int
var _b_snow_layer: int
var _b_rubble: int
var _b_sedge: int
var _b_sinter: int
var _b_vent: int
var _b_spruce_log: int
var _corals := PackedInt32Array()


func _init(gen: TerrainGenerator) -> void:
	_seed = gen.world_seed
	_registry = gen.registry
	_b_fluid = gen._b_fluid
	var reg := gen.registry
	_b_snow_layer = reg.block_num(gen._p["snow_layer"])
	_b_rubble = reg.block_num(&"rubble")
	_b_sedge = reg.block_num(&"sedge")
	_b_sinter = reg.block_num(&"sinter")
	_b_vent = reg.block_num(&"geyser_vent")
	_b_spruce_log = reg.block_num(&"spruce_log")
	for id in [&"coral_red", &"coral_yellow", &"coral_blue", &"coral_pink"]:
		_corals.append(reg.block_num(id))


func place(gen: TerrainGenerator, col: ChunkColumn, ctx: TerrainGenerator.Context) -> void:
	var w := ColumnWriter.new(col, _registry)
	_plants(gen, ctx, w)
	_features(gen, ctx, w)
	_trees(gen, ctx, w)
	_snow(gen, ctx, w)


func _plants(_gen: TerrainGenerator, ctx: TerrainGenerator.Context, w: ColumnWriter) -> void:
	var b_src := _gen.biomes
	var plantable := _gen.plantable
	for lz in 16:
		for lx in 16:
			var b := ctx.bio[lx + lz * 16]
			var plist: Array = b_src.plants[b]
			if plist.is_empty():
				continue
			var x := ctx.x0 + lx
			var z := ctx.z0 + lz
			var r := GenRandom.unit2(_gen.world_seed, x, z, 100)
			var acc := 0.0
			for p: Array in plist:
				acc += float(p[1])
				if r >= acc:
					continue
				var h := TerrainGenerator.ctx_height(ctx, lx, lz)
				var wl := TerrainGenerator.ctx_water(ctx, lx, lz)
				var wet := wl != TerrainGenerator.NO_WATER and h < wl
				if p[3]:
					# На воде: неглубоко и не подо льдом.
					if wet and wl - h <= 3 and w.get_block(x, wl + 1, z) == 0 and w.get_block(x, wl, z) == _b_fluid:
						w.set_block(x, wl + 1, z, p[0])
				elif not wet:
					var ground := w.get_block(x, h, z)
					var on: PackedInt32Array = p[2]
					var ok := on.has(ground) if not on.is_empty() else plantable[ground] == 1
					if ok and w.get_block(x, h + 1, z) == 0:
						w.set_block(x, h + 1, z, p[0])
				break


func _features(_gen: TerrainGenerator, ctx: TerrainGenerator.Context, w: ColumnWriter) -> void:
	var cp := ctx.cpos
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ncx := cp.x + dx
			var ncz := cp.y + dz
			for k in FEATURE_ATTEMPTS:
				var h0 := GenRandom.hash3(_gen.world_seed, ncx, ncz, k, 110)
				var x := ncx * 16 + (h0 & 15)
				var z := ncz * 16 + ((h0 >> 4) & 15)
				if x < ctx.x0 - 7 or x > ctx.x0 + 22 or z < ctx.z0 - 7 or z > ctx.z0 + 22:
					continue
				var b := _gen.biome_at(ctx, x, z)
				var flist: Array = _gen.biomes.features[b]
				for fi in flist.size():
					var f: Array = flist[fi]
					if GenRandom.unit(GenRandom.mix(h0 + 7 + fi)) >= float(f[1]) / FEATURE_ATTEMPTS:
						continue
					var surf := _gen.height_at(ctx, x, z)
					_feature(_gen, f[0], int(f[2]), b, x, surf.x, surf.y, z, GenRandom.mix(h0 + 31 + fi), ctx, w)


func _feature(_gen: TerrainGenerator, kind: StringName, block: int, biome: int, x: int, h: int, wl: int, z: int, hs: int,
		ctx: TerrainGenerator.Context, w: ColumnWriter) -> void:
	var wet := wl != TerrainGenerator.NO_WATER and h < wl
	var rng := GenRandom.rng(hs)
	match kind:
		&"fallen_log":
			if wet:
				return
			var tr: Array = _gen.biomes.trees[biome]
			var tl: PackedInt32Array = tr[0]
			var lg := _gen.trees.log_block[tl[0]] if not tl.is_empty() else _b_spruce_log
			var length := rng.randi_range(3, 6)
			var along_x := rng.randf() < 0.5
			for s in length:
				w.place_soft(x + (s if along_x else 0), h + 1, z + (0 if along_x else s), lg)
		&"rock_pile":
			if wet:
				return
			var r := rng.randf_range(2.0, 4.0)
			var ri := ceili(r)
			for ddx in range(-ri, ri + 1):
				for ddz in range(-ri, ri + 1):
					if ddx * ddx + ddz * ddz > r * r:
						continue
					var px := x + ddx
					var pz := z + ddz
					if not w.inside(px, pz):
						continue
					var ph := TerrainGenerator.ctx_height(ctx, px - ctx.x0, pz - ctx.z0)
					w.set_block(px, ph, pz, block if block >= 0 else _b_rubble)
					if GenRandom.unit2(_gen.world_seed, px, pz, 111) < 0.35:
						w.place_soft(px, ph + 1, pz, block if block >= 0 else _b_rubble)
		&"tussock":
			if wet or not w.inside(x, z):
				return
			w.place_soft(x, h + 1, z, _gen.biomes.top[biome])
			w.place_soft(x, h + 2, z, _b_sedge)
		&"boulder":
			if wet:
				return
			var r := rng.randf_range(1.0, 2.0)
			var ri := ceili(r)
			for ddy in range(-ri, ri + 1):
				for ddx in range(-ri, ri + 1):
					for ddz in range(-ri, ri + 1):
						if ddx * ddx + ddy * ddy * 1.4 + ddz * ddz <= r * r + 0.3:
							w.place_log(x + ddx, h + 1 + ddy, z + ddz, block if block >= 0 else _b_rubble)
		&"geyser":
			if wet:
				return
			for ddx in range(-2, 3):
				for ddz in range(-2, 3):
					var px := x + ddx
					var pz := z + ddz
					if not w.inside(px, pz) or ddx * ddx + ddz * ddz > 5:
						continue
					var ph := TerrainGenerator.ctx_height(ctx, px - ctx.x0, pz - ctx.z0)
					w.set_block(px, ph, pz, _b_vent if ddx == 0 and ddz == 0 else _b_sinter)
		&"coral":
			if not wet or wl - h < 3 or not w.inside(x, z):
				return
			var c := _corals[rng.randi_range(0, _corals.size() - 1)]
			for dy in rng.randi_range(1, 3):
				w.set_block(x, h + 1 + dy, z, c)
			w.set_block(x, h + 1, z, c)


func _trees(_gen: TerrainGenerator, ctx: TerrainGenerator.Context, w: ColumnWriter) -> void:
	var cp := ctx.cpos
	var reach := TreeBuilder.MAX_REACH
	var b_src := _gen.biomes
	var tb := _gen.trees
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ncx := cp.x + dx
			var ncz := cp.y + dz
			for k in TREE_ATTEMPTS:
				var h0 := GenRandom.hash3(_gen.world_seed, ncx, ncz, k, 90)
				var x := ncx * 16 + (h0 & 15)
				var z := ncz * 16 + ((h0 >> 4) & 15)
				if x < ctx.x0 - reach or x > ctx.x0 + 15 + reach or z < ctx.z0 - reach or z > ctx.z0 + 15 + reach:
					continue
				var b := _gen.biome_at(ctx, x, z)
				if GenRandom.unit(GenRandom.mix(h0 + 1)) * MAX_TREE_DENSITY >= b_src.tree_density[b]:
					continue
				var tr: Array = b_src.trees[b]
				var tl: PackedInt32Array = tr[0]
				var tw: PackedFloat32Array = tr[1]
				if tl.is_empty():
					continue
				var roll := GenRandom.unit(GenRandom.mix(h0 + 2)) * tw[tw.size() - 1]
				var t := tl[tl.size() - 1]
				for i in tl.size():
					if roll < tw[i]:
						t = tl[i]
						break
				var surf := _gen.height_at(ctx, x, z)
				var h := surf.x
				var wl := surf.y
				if wl != TerrainGenerator.NO_WATER and h < wl:
					if tb.in_water[t] != 1 or wl - h > 2:
						continue
				elif _gen.plantable[b_src.top[b]] != 1:
					continue
				tb.build(t, x, h + 1, z, GenRandom.mix(h0 + 3), w)


func _snow(_gen: TerrainGenerator, ctx: TerrainGenerator.Context, w: ColumnWriter) -> void:
	var b_src := _gen.biomes
	var shape := _gen.registry.block_shape
	var solid := _gen.registry.block_solid
	for lz in 16:
		for lx in 16:
			var b := ctx.bio[lx + lz * 16]
			if b_src.snow_cover[b] != 1:
				continue
			var x := ctx.x0 + lx
			var z := ctx.z0 + lz
			var h := TerrainGenerator.ctx_height(ctx, lx, lz)
			var wl := TerrainGenerator.ctx_water(ctx, lx, lz)
			if wl != TerrainGenerator.NO_WATER and h < wl:
				continue
			var ground := w.get_block(x, h, z)
			if ground <= 0 or solid[ground] != 1:
				continue
			var above := w.get_block(x, h + 1, z)
			if above == 0 or shape[above] == BlockDef.SHAPE_CROSS:
				w.set_block(x, h + 1, z, _b_snow_layer)
