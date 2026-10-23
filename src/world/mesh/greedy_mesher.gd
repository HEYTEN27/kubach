class_name GreedyMesher
extends RefCounted
## Greedy meshing секции 16×16×16 с отсечением невидимых граней (раздел 20 ТЗ).
##
## Соседние видимые грани одного блока в одной плоскости сливаются в один прямоугольник.
## Непрозрачные и cutout-блоки идут в поверхность "opaque", вода и стекло — в "transparent".
## Потокобезопасен: после создания только читает свои массивы.
##
## Снимок секции — массив [uniform: int, blocks: PackedInt32Array] (см. snapshot()).
## Соседи передаются в порядке NEIGHBOR_DIRS; null — воздух.

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

var _render: PackedByteArray
var _color: PackedColorArray


func _init(registry: ContentRegistry) -> void:
	_render = registry.block_render.duplicate()
	_color = registry.block_color.duplicate()


static func snapshot(section: ChunkSection) -> Array:
	if section == null:
		return [0, PackedInt32Array()]
	return [section.uniform, section.blocks]


## Результат: { "opaque": Array (массивы ArrayMesh) или [], "transparent": то же, "quads": int }.
func mesh_section(center: Array, neighbors: Array) -> Dictionary:
	var result := { "opaque": [], "transparent": [], "quads": 0 }
	var cu: int = center[0]
	var cb: PackedInt32Array = center[1]
	if cb.is_empty() and _render[cu] == BlockDef.RENDER_INVISIBLE:
		return result

	var pad := _build_padded(cu, cb, neighbors)
	if _is_enclosed(pad):
		return result
	# Однородная непрозрачная/жидкая секция: внутренние грани скрыты, смотрим только края.
	var boundary_only := cb.is_empty() and _render[cu] != BlockDef.RENDER_CUTOUT

	var opaque := _Surface.new()
	var transparent := _Surface.new()
	var mask := PackedInt32Array()
	mask.resize(256)

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
						if ra != BlockDef.RENDER_INVISIBLE:
							var b := pad[pi + nstep]
							var rb := _render[b]
							if rb == BlockDef.RENDER_INVISIBLE:
								m = a
							elif rb != BlockDef.RENDER_OPAQUE and (a != b or ra == BlockDef.RENDER_CUTOUT):
								m = a
						mask[uu + vv * 16] = m
						if m != 0:
							any = true
				if any:
					_greedy(mask, d, s, k, opaque, transparent)

	result["opaque"] = opaque.to_arrays()
	result["transparent"] = transparent.to_arrays()
	result["quads"] = opaque.quads + transparent.quads
	return result


## Все блоки секции и прилегающие слои соседей непрозрачны — видимых граней нет.
## Проверка в ~5 раз дешевле полного прохода и отсекает почти весь подземный камень.
func _is_enclosed(pad: PackedInt32Array) -> bool:
	for y in range(0, P):
		for z in range(0, P):
			var row := z * P + y * PY
			var edge_yz := y == 0 or y == P - 1 or z == 0 or z == P - 1
			for x in range(0, P):
				var edge := edge_yz or x == 0 or x == P - 1
				if edge:
					# Рёбра и углы массива не используются мешером; грани соседей — используются.
					var outside := int(y == 0 or y == P - 1) + int(z == 0 or z == P - 1) + int(x == 0 or x == P - 1)
					if outside != 1:
						continue
				if _render[pad[row + x]] != BlockDef.RENDER_OPAQUE:
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


func _greedy(mask: PackedInt32Array, d: int, s: int, k: int, opaque: _Surface, transparent: _Surface) -> void:
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
			surf.add_quad(d, s, k, uu, vv, w, h, _color[m])
			uu += w


## Накопитель вершин одной поверхности.
class _Surface:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var quads := 0

	func add_quad(d: int, s: int, k: int, u0: int, v0: int, w: int, h: int, color: Color) -> void:
		var f := float(k + (1 if s > 0 else 0))
		var n := Vector3.ZERO
		n[d] = float(s)
		var ua: int = GreedyMesher.AXIS_U[d]
		var va: int = GreedyMesher.AXIS_V[d]
		var base := verts.size()
		for c in 4:
			var cu := u0 + (w if c == 1 or c == 2 else 0)
			var cv := v0 + (h if c >= 2 else 0)
			var p := Vector3.ZERO
			p[d] = f
			p[ua] = float(cu)
			p[va] = float(cv)
			verts.append(p)
			normals.append(n)
			colors.append(color)
			uvs.append(Vector2(cu, cv))
		# Godot рисует лицевыми треугольники, обходимые по часовой стрелке (если смотреть
		# со стороны нормали). Обход c0→c1→c2 даёт векторное произведение e_u × e_v;
		# разворачиваем, если оно смотрит в ту же сторону, что и нормаль.
		var eu := Vector3.ZERO
		eu[ua] = 1.0
		var ev := Vector3.ZERO
		ev[va] = 1.0
		if eu.cross(ev).dot(n) > 0.0:
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
