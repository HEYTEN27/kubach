class_name VoxelLight
extends RefCounted
## Воксельное освещение (этап 3): свет неба и цветной свет блоков (лава, позже факелы и лампы).
##
## Свет колонны считается по области 3×3 колонны (48×48 по горизонтали): уровень падает на 1
## за блок, поэтому любой источник, достающий до центральной колонны (≤ 15 блоков), лежит в
## области, и результат точный. Уровни 0…15:
## - небо: сверху вниз уровень 15 проходит без потерь (минус light_filter блока), в стороны и
##   вверх — минус max(1, filter); filter ≥ 15 — свет не проходит;
## - блоки: три канала R, G, B = round(light_emission × light_color), распространяются так же.
##
## Результат по секциям центральной колонны: Color (свет однородный: r — небо, gba — блоки,
## доли 0…1) или PackedByteArray 18³ × RGBA8 (секция с полями в 1 блок — для 3D-текстуры
## шейдера, трилинейная выборка даёт мягкий свет). У непрозрачных клеток в текстуре — максимум
## соседей, чтобы стены не темнели к стыку.
##
## Это эталон на GDScript (медленный, для тестов и запасного пути). В игре работает NativeLight
## (native/kubach_native/src/native_light.cpp) — тот же алгоритм, результаты совпадают побайтно.

const OPAQUE := 15
const SIDE := 48
const PAD := 18
const PAD_VOLUME := 5832
const SKY_FULL := Color(1, 0, 0, 0)
const DARK := Color(0, 0, 0, 0)

var _att := PackedByteArray()    # блок → light_filter (0…15)
var _emit := PackedByteArray()   # блок → 3 байта: уровни R, G, B


func _init(registry: ContentRegistry = null) -> void:
	if registry != null:
		setup(registry.block_light_filter, emission_table(registry))


## Лучший доступный расчёт света: NativeLight (C++), если расширение загружено, иначе этот.
## KUBACH_NO_NATIVE=1 — принудительно GDScript (медленно: секунды на колонну).
static func create_best(registry: ContentRegistry) -> Object:
	if ClassDB.class_exists(&"NativeLight") and not OS.has_environment("KUBACH_NO_NATIVE"):
		var l: Object = ClassDB.instantiate(&"NativeLight")
		l.call(&"setup", registry.block_light_filter, emission_table(registry))
		return l
	return VoxelLight.new(registry)


static func is_native(light: Object) -> bool:
	return light != null and light.get_class() == "NativeLight"


## Таблица излучения: на блок 3 байта (R, G, B) — уровень × цвет света.
static func emission_table(registry: ContentRegistry) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(registry.block_count() * 3)
	for num in range(1, registry.block_count()):
		var b := registry.block_by_num(num)
		if b.light_emission <= 0:
			continue
		var c := b.light_color
		t[num * 3] = roundi(b.light_emission * c.r)
		t[num * 3 + 1] = roundi(b.light_emission * c.g)
		t[num * 3 + 2] = roundi(b.light_emission * c.b)
	return t


func setup(att: PackedByteArray, emit: PackedByteArray) -> void:
	_att = att.duplicate()
	_att[0] = 0
	_emit = emit.duplicate()


## columns — 9 колонн области в порядке (dz, dx) от (−1, −1) до (1, 1); у каждой — массив из
## 36 снимков секций (GreedyMesher.snapshot) или null (колонна не загружена — считается
## непрозрачной). Возвращает массив из 36 элементов: Color или PackedByteArray (см. описание).
func light_column(columns: Array) -> Array:
	var out := []
	out.resize(WorldConst.SECTIONS_PER_COLUMN)
	# Вертикальный диапазон области: от нижней непустой секции до верхней + 1 секция воздуха.
	var lo := WorldConst.SECTIONS_PER_COLUMN
	var hi := -1
	for col: Variant in columns:
		if col == null:
			continue
		for si in WorldConst.SECTIONS_PER_COLUMN:
			if _non_air(col[si]):
				lo = mini(lo, si)
				hi = maxi(hi, si)
	if hi < 0:
		out.fill(SKY_FULL)
		return out
	var y0 := lo * 16
	var sy := (hi + 1 - lo) * 16 + 1   # + слой воздуха сверху
	var vol := SIDE * SIDE * sy
	var att := PackedByteArray()
	att.resize(vol)
	var emit := PackedByteArray()
	emit.resize(vol * 3)
	_fill_region(columns, lo, hi, att, emit, sy)
	var sky := propagate_sky(att, SIDE, sy, SIDE)
	var rgb := []
	for ch in 3:
		rgb.append(propagate_block(att, emit, ch, SIDE, sy, SIDE))
	for si in WorldConst.SECTIONS_PER_COLUMN:
		if si > hi:
			out[si] = SKY_FULL
		elif si < lo:
			out[si] = DARK
		else:
			out[si] = _extract(att, sky, rgb, sy, si * 16 - y0)
	return out


func _non_air(snap: Variant) -> bool:
	if snap == null:
		return false
	return snap[0] != 0 or not (snap[1] as PackedInt32Array).is_empty()


## Заполнение области: att — фильтр (у незагруженных колонн — OPAQUE), emit — R, G, B.
func _fill_region(columns: Array, lo: int, hi: int, att: PackedByteArray, emit: PackedByteArray, sy: int) -> void:
	var plane := SIDE * SIDE
	for ci in 9:
		var ox := (ci % 3) * 16
		var oz := (ci / 3) * 16
		var col: Variant = columns[ci]
		for si in range(lo, hi + 1):
			var ry0 := (si - lo) * 16
			if col == null:
				for ly in 16:
					for lz in 16:
						var base := ox + (oz + lz) * SIDE + (ry0 + ly) * plane
						for lx in 16:
							att[base + lx] = OPAQUE
				continue
			var snap: Variant = col[si]
			if snap == null:
				continue
			var u: int = snap[0]
			var bl: PackedInt32Array = snap[1]
			for ly in 16:
				for lz in 16:
					var base := ox + (oz + lz) * SIDE + (ry0 + ly) * plane
					var src := (lz << 4) | (ly << 8)
					for lx in 16:
						var b := u if bl.is_empty() else bl[src + lx]
						if b == 0:
							continue
						var i := base + lx
						att[i] = _att[b]
						var e := b * 3
						emit[i * 3] = _emit[e]
						emit[i * 3 + 1] = _emit[e + 1]
						emit[i * 3 + 2] = _emit[e + 2]


## Свет неба в коробке sx × sy × sz (индекс x + z·sx + y·sx·sz): сверху открыто небо.
static func propagate_sky(att: PackedByteArray, sx: int, sy: int, sz: int) -> PackedByteArray:
	var plane := sx * sz
	var light := PackedByteArray()
	light.resize(att.size())
	var queue := PackedInt32Array()
	for z in sz:
		for x in sx:
			var level := 15
			var y := sy - 1
			while y >= 0 and level > 0:
				var i := x + z * sx + y * plane
				var f := att[i]
				if f >= OPAQUE:
					break
				level -= f
				if level <= 0:
					break
				light[i] = level
				queue.append(i)
				y -= 1
	_spread(att, light, queue, sx, sy, sz, true)
	return light


## Свет блоков одного канала (ch: 0 — R, 1 — G, 2 — B).
static func propagate_block(att: PackedByteArray, emit: PackedByteArray, ch: int, sx: int, sy: int, sz: int) -> PackedByteArray:
	var light := PackedByteArray()
	light.resize(att.size())
	var queue := PackedInt32Array()
	for i in att.size():
		var e := emit[i * 3 + ch]
		if e > 0:
			light[i] = e
			queue.append(i)
	if not queue.is_empty():
		_spread(att, light, queue, sx, sy, sz, false)
	return light


## Поиск в ширину: свет переходит в соседа с уровнем l − max(1, filter); у неба уровень 15
## идёт вниз без потерь (минус filter).
static func _spread(att: PackedByteArray, light: PackedByteArray, queue: PackedInt32Array, sx: int, sy: int, sz: int,
		sky: bool) -> void:
	var plane := sx * sz
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var l := light[i]
		if l <= 1:
			continue
		var x := i % sx
		var z := (i / sx) % sz
		var y := i / plane
		for d in 6:
			var n := 0
			match d:
				0:
					if x == 0:
						continue
					n = i - 1
				1:
					if x == sx - 1:
						continue
					n = i + 1
				2:
					if z == 0:
						continue
					n = i - sx
				3:
					if z == sz - 1:
						continue
					n = i + sx
				4:
					if y == 0:
						continue
					n = i - plane
				5:
					if y == sy - 1:
						continue
					n = i + plane
			var f := att[n]
			if f >= OPAQUE:
				continue
			var nl := 0
			if sky and d == 4 and l == 15:
				nl = 15 - f
			else:
				nl = l - maxi(1, f)
			if nl > light[n]:
				light[n] = nl
				queue.append(n)


## Секция центральной колонны (ry — её низ в координатах области): 18³ RGBA8 или Color.
func _extract(att: PackedByteArray, sky: PackedByteArray, rgb: Array, sy: int, ry: int) -> Variant:
	var plane := SIDE * SIDE
	var data := PackedByteArray()
	data.resize(PAD_VOLUME * 4)
	var r: PackedByteArray = rgb[0]
	var g: PackedByteArray = rgb[1]
	var b: PackedByteArray = rgb[2]
	var first := -1
	var uniform := true
	var o := 0
	for py in PAD:
		var y := ry + py - 1
		for pz in PAD:
			var z := 15 + pz
			for px in PAD:
				var x := 15 + px
				var v := 0
				if y >= sy:
					v = 15
				elif y >= 0:
					var i := x + z * SIDE + y * plane
					if att[i] >= OPAQUE:
						v = _neighbor_max(att, sky, r, g, b, x, y, z, sy)
					else:
						v = (sky[i] << 24) | (r[i] << 16) | (g[i] << 8) | b[i]
				data[o] = ((v >> 24) & 15) * 17
				data[o + 1] = ((v >> 16) & 15) * 17
				data[o + 2] = ((v >> 8) & 15) * 17
				data[o + 3] = (v & 15) * 17
				if first < 0:
					first = v
				elif v != first:
					uniform = false
				o += 4
	if uniform:
		return Color(((first >> 24) & 15) / 15.0, ((first >> 16) & 15) / 15.0, ((first >> 8) & 15) / 15.0, (first & 15) / 15.0)
	return data


## Свет внутри непрозрачной клетки для текстуры: поканальный максимум прозрачных соседей.
static func _neighbor_max(att: PackedByteArray, sky: PackedByteArray, r: PackedByteArray, g: PackedByteArray,
		b: PackedByteArray, x: int, y: int, z: int, sy: int) -> int:
	var plane := SIDE * SIDE
	var ms := 0
	var mr := 0
	var mg := 0
	var mb := 0
	for d in 6:
		var nx := x
		var ny := y
		var nz := z
		match d:
			0: nx -= 1
			1: nx += 1
			2: nz -= 1
			3: nz += 1
			4: ny -= 1
			5: ny += 1
		if nx < 0 or nx >= SIDE or nz < 0 or nz >= SIDE or ny < 0:
			continue
		if ny >= sy:
			ms = 15
			continue
		var n := nx + nz * SIDE + ny * plane
		if att[n] >= OPAQUE:
			continue
		ms = maxi(ms, sky[n])
		mr = maxi(mr, r[n])
		mg = maxi(mg, g[n])
		mb = maxi(mb, b[n])
	return (ms << 24) | (mr << 16) | (mg << 8) | mb


## Срезы 3D-текстуры: по глубине идёт Y (данные лежат слоями y), в срезе — (x, z).
## Шейдер поэтому берёт координаты текстуры как (x, z, y).
static func make_images(data: PackedByteArray) -> Array[Image]:
	var images: Array[Image] = []
	var slice := PAD * PAD * 4
	for y in PAD:
		images.append(Image.create_from_data(PAD, PAD, false, Image.FORMAT_RGBA8, data.slice(y * slice, (y + 1) * slice)))
	return images


## Готовая 3D-текстура 18³ из данных секции.
static func make_texture(data: PackedByteArray) -> ImageTexture3D:
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, PAD, PAD, PAD, false, make_images(data))
	return tex
