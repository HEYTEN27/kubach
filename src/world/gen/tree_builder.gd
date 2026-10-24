class_name TreeBuilder
extends RefCounted
## Формы деревьев (data/trees.json → shape). Дерево строится целиком из своего хэша, а в колонну
## записываются только блоки внутри неё — поэтому крона через границу колонн совпадает.

const SHAPES: Array[StringName] = [&"conifer", &"pine", &"round", &"oval", &"broad", &"willow", &"bush",
	&"palm", &"acacia", &"jungle", &"mangrove", &"bamboo", &"mushroom"]
## Насколько далеко дерево может выйти за точку посадки (крона + ветви).
const MAX_REACH := 10

var count := 0
var ids: Array[StringName] = []
var index := {}  # StringName -> int
var log_block := PackedInt32Array()
var leaves_block := PackedInt32Array()
var shape := PackedByteArray()
var h_min := PackedInt32Array()
var h_max := PackedInt32Array()
var width := PackedInt32Array()
var radius := PackedFloat32Array()
var in_water := PackedByteArray()
var _seed := 0


func _init(registry: ContentRegistry, world_seed: int) -> void:
	_seed = world_seed
	for e in registry.get_entries("trees"):
		index[StringName(e["id"])] = count
		count += 1
		ids.append(StringName(e["id"]))
		log_block.append(registry.block_num(e["log"]))
		leaves_block.append(registry.block_num(e["leaves"]))
		shape.append(SHAPES.find(StringName(e["shape"])))
		h_min.append(e["height"]["min"])
		h_max.append(e["height"]["max"])
		width.append(e["trunk_width"])
		radius.append(e["canopy_radius"])
		in_water.append(1 if e["in_water"] else 0)


## Строит дерево `t` с основанием ствола в (x, y, z) — y — первый блок над землёй.
func build(t: int, x: int, y: int, z: int, h_seed: int, w: ColumnWriter) -> void:
	var rng := GenRandom.rng(h_seed)
	var hgt := rng.randi_range(h_min[t], h_max[t])
	var r := radius[t] * rng.randf_range(0.85, 1.15)
	var lg := log_block[t]
	var lv := leaves_block[t]
	var tw := width[t]
	match SHAPES[shape[t]]:
		&"conifer":
			# Ствол кончается под верхушкой: верхние ярусы — хвоя вокруг ствола (не «шест»).
			_trunk(w, x, y, z, hgt - 1, tw, lg)
			var start := y + maxi(2, int(hgt * 0.22))
			var top := y + hgt
			for yy in range(start, top + 2):
				var k := float(top + 1 - yy) / float(top + 1 - start)
				var rr := r * k
				if (yy - start) % 2 == 1:
					rr *= 0.7
				_disc(w, x, yy, z, maxf(rr, 1.05 if yy < top else 0.6), tw, lv, 0.0)
			w.place_soft(x, top + 2, z, lv)
		&"pine":
			_trunk(w, x, y, z, hgt, tw, lg)
			var top := y + hgt
			for dy in range(-3, 2):
				var rr := r * (1.0 - absf(dy + 1) / 3.5)
				_disc(w, x, top + dy, z, maxf(rr, 0.8), tw, lv, 0.15)
		&"round":
			_trunk(w, x, y, z, hgt, tw, lg)
			_blob(w, x, y + hgt - 1, z, r, r * 0.9, lv, 0.12, tw)
		&"oval":
			_trunk(w, x, y, z, hgt, tw, lg)
			_blob(w, x, y + hgt - int(r * 0.8), z, r, r * 1.7, lv, 0.1, tw)
		&"broad":
			_trunk(w, x, y, z, hgt, tw, lg)
			for i in rng.randi_range(2, 4):
				var a := rng.randf() * TAU
				var bl := int(r * 0.6)
				var by := y + hgt - rng.randi_range(1, 3)
				for s in range(1, bl + 1):
					w.place_log(x + roundi(cos(a) * s), by + s / 2, z + roundi(sin(a) * s), lg)
			_blob(w, x, y + hgt, z, r, r * 0.6, lv, 0.12, tw)
		&"willow":
			_trunk(w, x, y, z, hgt, tw, lg)
			var cy := y + hgt
			_blob(w, x, cy, z, r, r * 0.55, lv, 0.1, tw)
			# Свисающие ветви по краю кроны.
			for i in 14:
				var a := TAU * i / 14.0
				var hx := x + roundi(cos(a) * r)
				var hz := z + roundi(sin(a) * r)
				var drop_len := 2 + int(GenRandom.unit3(_seed, hx, cy, hz, 61) * 4.0)
				for d in drop_len:
					w.place_soft(hx, cy - d, hz, lv)
		&"bush":
			w.place_log(x, y, z, lg)
			_blob(w, x, y + hgt / 2, z, r, maxf(1.0, hgt * 0.7), lv, 0.15, 1)
		&"palm":
			var lean_a := rng.randf() * TAU
			var lean := rng.randf_range(1.0, 3.0)
			var tx := x
			var tz := z
			for i in hgt:
				var k := float(i * i) / float(hgt * hgt)
				tx = x + roundi(cos(lean_a) * lean * k)
				tz = z + roundi(sin(lean_a) * lean * k)
				w.place_log(tx, y + i, tz, lg)
			var ty := y + hgt
			w.place_soft(tx, ty, tz, lv)
			for i in 7:
				var a := TAU * i / 7.0 + rng.randf() * 0.3
				var fl := int(r) + 1
				for s in range(1, fl + 1):
					var drop := 0 if s < fl - 1 else 1
					w.place_soft(tx + roundi(cos(a) * s), ty - drop, tz + roundi(sin(a) * s), lv)
		&"acacia":
			var bend_a := rng.randf() * TAU
			var bend := rng.randi_range(1, 2)
			var half := hgt / 2
			for i in hgt:
				var off := 0 if i < half else bend
				w.place_log(x + roundi(cos(bend_a) * off), y + i, z + roundi(sin(bend_a) * off), lg)
			var cx := x + roundi(cos(bend_a) * bend)
			var cz := z + roundi(sin(bend_a) * bend)
			_disc(w, cx, y + hgt, cz, r, 1, lv, 0.08)
			_disc(w, cx, y + hgt + 1, cz, r * 0.6, 1, lv, 0.1)
		&"jungle":
			_trunk(w, x, y, z, hgt, tw, lg)
			for i in 3:
				var a := rng.randf() * TAU
				var by := y + hgt - rng.randi_range(4, 9)
				var ex := x + roundi(cos(a) * 3.0)
				var ez := z + roundi(sin(a) * 3.0)
				for s in range(1, 4):
					w.place_log(x + roundi(cos(a) * s), by + s / 2, z + roundi(sin(a) * s), lg)
				_blob(w, ex, by + 2, ez, 2.2, 1.4, lv, 0.1, 1)
			_blob(w, x, y + hgt, z, r, r * 0.55, lv, 0.1, tw)
		&"mangrove":
			# Корни-ходули: ствол начинается выше, от него арками вниз расходятся корни.
			var lift := 3
			for i in 4:
				var a := TAU * i / 4.0 + rng.randf() * 0.5
				for s in range(0, 4):
					w.place_log(x + roundi(cos(a) * s * 0.8), y + lift - s, z + roundi(sin(a) * s * 0.8), lg)
			_trunk(w, x, y + lift, z, hgt - lift, 1, lg)
			_blob(w, x, y + hgt, z, r, r * 0.6, lv, 0.12, 1)
		&"bamboo":
			for i in hgt:
				w.place_log(x, y + i, z, lg)
			_blob(w, x, y + hgt - 1, z, 1.2, 1.5, lv, 0.3, 1)
		&"mushroom":
			_trunk(w, x, y, z, hgt, 1, lg)
			var top := y + hgt
			if r > 3.5:
				_disc(w, x, top, z, r, 1, lv, 0.0)
			else:
				for dy in range(0, int(r) + 1):
					var rr := sqrt(maxf(0.0, r * r - dy * dy * 2.0))
					_ring(w, x, top - int(r * 0.5) + dy, z, rr, lv)
				_disc(w, x, top + int(r * 0.5) + 1, z, r * 0.5, 1, lv, 0.0)


func _trunk(w: ColumnWriter, x: int, y: int, z: int, hgt: int, tw: int, lg: int) -> void:
	for i in hgt:
		for dx in tw:
			for dz in tw:
				w.place_log(x + dx, y + i, z + dz, lg)


## Горизонтальный круг листвы (с центром между блоками для ствола 2×2).
func _disc(w: ColumnWriter, x: int, y: int, z: int, r: float, tw: int, lv: int, holes: float) -> void:
	var c := (tw - 1) * 0.5
	var ri := ceili(r + c)
	for dx in range(-ri, ri + tw):
		for dz in range(-ri, ri + tw):
			var fx := dx - c
			var fz := dz - c
			if fx * fx + fz * fz > r * r + 0.5 or not w.inside(x + dx, z + dz):
				continue
			if holes > 0.0 and GenRandom.unit3(_seed, x + dx, y, z + dz, 62) < holes:
				continue
			w.place_soft(x + dx, y, z + dz, lv)


func _ring(w: ColumnWriter, x: int, y: int, z: int, r: float, lv: int) -> void:
	var ri := ceili(r)
	for dx in range(-ri, ri + 1):
		for dz in range(-ri, ri + 1):
			var d := sqrt(float(dx * dx + dz * dz))
			if d <= r + 0.5 and d >= r - 1.2:
				w.place_soft(x + dx, y, z + dz, lv)


## Эллипсоид листвы: горизонтальный радиус rh, вертикальный rv.
func _blob(w: ColumnWriter, x: int, y: int, z: int, rh: float, rv: float, lv: int, holes: float, tw: int) -> void:
	var c := (tw - 1) * 0.5
	var ih := ceili(rh + c)
	var iv := ceili(rv)
	# Крона целиком вне колонны — ничего не делаем.
	if x + ih + tw < w.x0 or x - ih > w.x0 + 15 or z + ih + tw < w.z0 or z - ih > w.z0 + 15:
		return
	for dy in range(-iv, iv + 1):
		for dx in range(-ih, ih + tw):
			if not w.inside(x + dx, w.z0):
				continue
			for dz in range(-ih, ih + tw):
				if not w.inside(x + dx, z + dz):
					continue
				var fx := (dx - c) / rh
				var fz := (dz - c) / rh
				var fy := float(dy) / maxf(rv, 0.5)
				var d := fx * fx + fy * fy + fz * fz
				if d > 1.0:
					continue
				if d > 0.6 and GenRandom.unit3(_seed, x + dx, y + dy, z + dz, 63) < holes * 2.0:
					continue
				w.place_soft(x + dx, y + dy, z + dz, lv)
