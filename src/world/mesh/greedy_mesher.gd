class_name GreedyMesher
extends RefCounted
## Greedy meshing секции 16×16×16 с отсечением невидимых граней (раздел 20 ТЗ).
##
## Соседние видимые грани одного блока в одной плоскости сливаются в один прямоугольник.
## Поверхности: "opaque" — непрозрачные и cutout-кубы и тонкие слои, "transparent" — вода, лёд,
## стекло, "plants" — растения крестом (двусторонние). Блоки с тонированием получают цвет травы
## или листвы биома по вершинам — плавный переход между биомами без потери слияния граней.
## Потокобезопасен: после создания только читает свои массивы.
##
## Снимок секции — [uniform, blocks, all_opaque, has_special] (см. snapshot()).
## Соседи — в порядке NEIGHBOR_DIRS; null — воздух.

## −X, +X, −Y, +Y, −Z, +Z.
const NEIGHBOR_DIRS: Array[Vector3i] = [
	Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0),
	Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1),
]

# Массив с полями 18×18×18: индекс (x+1) + (z+1)*18 + (y+1)*324.
const P := 18
const PY := 324
const PAD_VOLUME := 5832
# Шаги в массиве с полями по осям x, y, z.
const STRIDE: Array[int] = [1, PY, P]
# Оси u, v для каждой оси нормали d: x → (z, y), y → (x, z), z → (x, y).
const AXIS_U: Array[int] = [2, 0, 0]
const AXIS_V: Array[int] = [1, 2, 1]
const TINT_N := 5

var _render: PackedByteArray
var _shape: PackedByteArray
var _color: PackedColorArray
var _tint: PackedByteArray
var _tint_strength: PackedFloat32Array
var _layer_h: PackedFloat32Array
var _opaque: PackedByteArray


func _init(registry: ContentRegistry) -> void:
	_render = registry.block_render.duplicate()
	_shape = registry.block_shape.duplicate()
	_color = registry.block_color.duplicate()
	_tint = registry.block_tint.duplicate()
	_tint_strength = registry.block_tint_strength.duplicate()
	_layer_h = registry.block_layer_height.duplicate()
	_opaque = registry.block_opaque.duplicate()


## Лучший доступный мешер: нативный (C++ GDExtension, native/kubach_native), если библиотека
## загружена, иначе этот, на GDScript. Результаты у них одинаковые (см. test_native_mesher.gd).
## Переменная окружения KUBACH_NO_NATIVE=1 принудительно включает GDScript.
static func create_best(registry: ContentRegistry) -> Object:
	if ClassDB.class_exists(&"NativeMesher") and not OS.has_environment("KUBACH_NO_NATIVE"):
		var m: Object = ClassDB.instantiate(&"NativeMesher")
		m.call(&"setup", registry.block_render, registry.block_shape, registry.block_color, registry.block_tint,
			registry.block_tint_strength, registry.block_layer_height, registry.block_opaque)
		return m
	return GreedyMesher.new(registry)


static func is_native(mesher: Object) -> bool:
	return mesher != null and mesher.get_class() == "NativeMesher"


static func snapshot(section: ChunkSection) -> Array:
	if section == null:
		return [0, PackedInt32Array(), false, false]
	return [section.uniform, section.blocks, section.all_opaque, section.has_special]


## Результат: { "opaque", "transparent", "plants": массивы ArrayMesh или [], "quads": int }.
## tints — сетка цветов колонны (ChunkColumn.tints), season — 0…3, origin — мировой угол секции.
func mesh_section(center: Array, neighbors: Array, tints: PackedColorArray = PackedColorArray(),
		season: int = 1, origin: Vector3i = Vector3i.ZERO) -> Dictionary:
	var result := { "opaque": [], "transparent": [], "plants": [], "quads": 0 }
	var cu: int = center[0]
	var cb: PackedInt32Array = center[1]
	if cb.is_empty() and _render[cu] == BlockDef.RENDER_INVISIBLE:
		return result
	if center[2] and _all_neighbors_opaque(neighbors):
		return result

	var pad := _build_padded(cu, cb, neighbors)
	# Однородная непрозрачная/жидкая секция: внутренние грани скрыты, смотрим только края.
	var boundary_only := cb.is_empty() and _render[cu] != BlockDef.RENDER_CUTOUT and _shape[cu] == BlockDef.SHAPE_CUBE

	var opaque := _Surface.new()
	var transparent := _Surface.new()
	var plants := _Surface.new()
	var mask := PackedInt32Array()
	mask.resize(256)
	var tinting := tints.size() == 8 * TINT_N * TINT_N

	for d in 3:
		var sd: int = STRIDE[d]
		var u_axis: int = AXIS_U[d]
		var v_axis: int = AXIS_V[d]
		var su: int = STRIDE[u_axis]
		var sv: int = STRIDE[v_axis]
		for s in [-1, 1]:
			var nstep: int = s * sd
			var k_from := 0
			var k_to := 16
			if boundary_only:
				k_from = 0 if s < 0 else 15
				k_to = k_from + 1
			for k in range(k_from, k_to):
				var any := false
				var base := (k + 1) * sd + su + sv
				for vv in 16:
					var row := base + vv * sv
					for uu in 16:
						var pi := row + uu * su
						var a := pad[pi]
						var m := 0
						var ra := _render[a]
						if ra != BlockDef.RENDER_INVISIBLE and _shape[a] == BlockDef.SHAPE_CUBE:
							var b := pad[pi + nstep]
							var rb := _render[b]
							if rb == BlockDef.RENDER_INVISIBLE:
								m = a
							elif _opaque[b] != 1 and (a != b or ra == BlockDef.RENDER_CUTOUT):
								m = a
						mask[uu + vv * 16] = m
						if m != 0:
							any = true
				if any:
					_greedy(mask, d, s, k, opaque, transparent, tints if tinting else PackedColorArray(), season)

	if center[3]:
		_special(cb, cu, pad, opaque, plants, tints if tinting else PackedColorArray(), season, origin)

	result["opaque"] = opaque.to_arrays()
	result["transparent"] = transparent.to_arrays()
	result["plants"] = plants.to_arrays()
	result["quads"] = opaque.quads + transparent.quads + plants.quads
	return result


func _all_neighbors_opaque(neighbors: Array) -> bool:
	for nb: Variant in neighbors:
		if nb == null or not nb[2]:
			return false
	return true


func _build_padded(cu: int, cb: PackedInt32Array, neighbors: Array) -> PackedInt32Array:
	var pad := PackedInt32Array()
	pad.resize(PAD_VOLUME)
	for y in 16:
		for z in 16:
			var dst := 1 + (z + 1) * P + (y + 1) * PY
			var src := (z << 4) | (y << 8)
			if cb.is_empty():
				for x in 16:
					pad[dst + x] = cu
			else:
				for x in 16:
					pad[dst + x] = cb[src + x]
	# Грани соседей: слой, прилегающий к секции.
	for i in 6:
		var nb: Variant = neighbors[i]
		if nb == null:
			continue
		var nu: int = nb[0]
		var nbl: PackedInt32Array = nb[1]
		if nbl.is_empty() and nu == 0:
			continue
		var dir: Vector3i = NEIGHBOR_DIRS[i]
		for a in 16:
			for b in 16:
				# (x, y, z) в координатах секции-соседа и в координатах массива с полями.
				var x: int
				var y: int
				var z: int
				var px: int
				var py: int
				var pz: int
				if dir.x != 0:
					x = 15 if dir.x < 0 else 0
					y = a
					z = b
					px = -1 if dir.x < 0 else 16
					py = a
					pz = b
				elif dir.y != 0:
					x = a
					y = 15 if dir.y < 0 else 0
					z = b
					px = a
					py = -1 if dir.y < 0 else 16
					pz = b
				else:
					x = a
					y = b
					z = 15 if dir.z < 0 else 0
					px = a
					py = b
					pz = -1 if dir.z < 0 else 16
				var v := nu if nbl.is_empty() else nbl[x | (z << 4) | (y << 8)]
				pad[(px + 1) + (pz + 1) * P + (py + 1) * PY] = v
	return pad


func _greedy(mask: PackedInt32Array, d: int, s: int, k: int, opaque: _Surface, transparent: _Surface,
		tints: PackedColorArray, season: int) -> void:
	var ua: int = AXIS_U[d]
	var va: int = AXIS_V[d]
	var f := float(k + (1 if s > 0 else 0))
	for vv in 16:
		var uu := 0
		while uu < 16:
			var m := mask[uu + vv * 16]
			if m == 0:
				uu += 1
				continue
			var w := 1
			while uu + w < 16 and mask[uu + w + vv * 16] == m:
				w += 1
			var h := 1
			var grow := true
			while vv + h < 16 and grow:
				var row := (vv + h) * 16
				for i in w:
					if mask[uu + i + row] != m:
						grow = false
						break
				if grow:
					h += 1
			for j in h:
				for i in w:
					mask[uu + i + (vv + j) * 16] = 0
			var r := _render[m]
			var surf := transparent if r == BlockDef.RENDER_TRANSLUCENT or r == BlockDef.RENDER_LIQUID else opaque
			var n := Vector3.ZERO
			n[d] = float(s)
			var pts := PackedVector3Array()
			var cols := PackedColorArray()
			for c in 4:
				var p := Vector3.ZERO
				p[d] = f
				p[ua] = float(uu + (w if c == 1 or c == 2 else 0))
				p[va] = float(vv + (h if c >= 2 else 0))
				pts.append(p)
				cols.append(_block_color(m, p.x, p.z, tints, season))
			surf.add_quad(pts, n, cols)
			uu += w


## Растения крестом и тонкие слои (снег, мох, кувшинки).
func _special(cb: PackedInt32Array, cu: int, pad: PackedInt32Array, opaque: _Surface, plants: _Surface,
		tints: PackedColorArray, season: int, origin: Vector3i) -> void:
	for y in 16:
		for z in 16:
			for x in 16:
				var b := cu if cb.is_empty() else cb[x | (z << 4) | (y << 8)]
				var sh := _shape[b]
				if sh == BlockDef.SHAPE_CUBE:
					continue
				var c := _block_color(b, x + 0.5, z + 0.5, tints, season)
				if sh == BlockDef.SHAPE_CROSS:
					var hsh := GenRandom.hash3(0, origin.x + x, origin.y + y, origin.z + z, 5)
					var ox := (GenRandom.unit(hsh) - 0.5) * 0.3
					var oz := (GenRandom.unit(GenRandom.mix(hsh)) - 0.5) * 0.3
					var x0 := x + 0.15 + ox
					var x1 := x + 0.85 + ox
					var z0 := z + 0.15 + oz
					var z1 := z + 0.85 + oz
					var cols := PackedColorArray([c, c, c, c])
					var n1 := Vector3(1, 0, -1).normalized()
					var n2 := Vector3(1, 0, 1).normalized()
					plants.add_quad(PackedVector3Array([Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x1, y + 1, z1), Vector3(x0, y + 1, z0)]),
						n1, cols)
					plants.add_quad(PackedVector3Array([Vector3(x0, y, z1), Vector3(x1, y, z0), Vector3(x1, y + 1, z0), Vector3(x0, y + 1, z1)]),
						n2, cols)
				else:
					_layer(b, x, y, z, pad, opaque, c)


func _layer(b: int, x: int, y: int, z: int, pad: PackedInt32Array, opaque: _Surface, c: Color) -> void:
	var h := _layer_h[b]
	var top := y + h
	var cols := PackedColorArray([c, c, c, c])
	var pi := (x + 1) + (z + 1) * P + (y + 1) * PY
	# Верх слоя.
	opaque.add_quad(PackedVector3Array([Vector3(x, top, z), Vector3(x + 1, top, z), Vector3(x + 1, top, z + 1), Vector3(x, top, z + 1)]),
		Vector3.UP, cols)
	# Бока — если сосед не закрывает.
	if _opaque[pad[pi - 1]] != 1:
		opaque.add_quad(PackedVector3Array([Vector3(x, y, z), Vector3(x, y, z + 1), Vector3(x, top, z + 1), Vector3(x, top, z)]),
			Vector3.LEFT, cols)
	if _opaque[pad[pi + 1]] != 1:
		opaque.add_quad(PackedVector3Array([Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1), Vector3(x + 1, top, z + 1), Vector3(x + 1, top, z)]),
			Vector3.RIGHT, cols)
	if _opaque[pad[pi - P]] != 1:
		opaque.add_quad(PackedVector3Array([Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, top, z), Vector3(x, top, z)]),
			Vector3.FORWARD, cols)
	if _opaque[pad[pi + P]] != 1:
		opaque.add_quad(PackedVector3Array([Vector3(x, y, z + 1), Vector3(x + 1, y, z + 1), Vector3(x + 1, top, z + 1), Vector3(x, top, z + 1)]),
			Vector3.BACK, cols)


## Цвет блока в точке (локальные x, z колонны): map_color, смешанный с цветом биома.
func _block_color(b: int, lx: float, lz: float, tints: PackedColorArray, season: int) -> Color:
	var t := _tint[b]
	var base := _color[b]
	if t == BlockDef.TINT_NONE or tints.is_empty():
		return base
	var ch := season * 2 + (1 if t == BlockDef.TINT_FOLIAGE else 0)
	var off := ch * TINT_N * TINT_N
	var gx := clampf(lx / 4.0, 0.0, 4.0)
	var gz := clampf(lz / 4.0, 0.0, 4.0)
	var ix := mini(int(gx), 3)
	var iz := mini(int(gz), 3)
	var fx := gx - ix
	var fz := gz - iz
	var c0 := tints[off + iz * TINT_N + ix].lerp(tints[off + iz * TINT_N + ix + 1], fx)
	var c1 := tints[off + (iz + 1) * TINT_N + ix].lerp(tints[off + (iz + 1) * TINT_N + ix + 1], fx)
	return base.lerp(c0.lerp(c1, fz), _tint_strength[b])


## Накопитель вершин одной поверхности.
class _Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var quads := 0

	## Четыре угла по кругу. Godot рисует лицевыми треугольники, обходимые по часовой стрелке
	## (если смотреть со стороны нормали): обход разворачивается, если (p1−p0)×(p2−p0) смотрит
	## туда же, куда нормаль.
	func add_quad(pts: PackedVector3Array, n: Vector3, cols: PackedColorArray) -> void:
		var flip := (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0
		var base := verts.size()
		var uv_axes := Vector2i(0, 2) if absf(n.y) > 0.5 else (Vector2i(2, 1) if absf(n.x) > 0.5 else Vector2i(0, 1))
		for c in 4:
			verts.append(pts[c])
			normals.append(n)
			colors.append(cols[c])
			uvs.append(Vector2(pts[c][uv_axes.x], pts[c][uv_axes.y]))
		if flip:
			indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		quads += 1

	func to_arrays() -> Array:
		if quads == 0:
			return []
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays
