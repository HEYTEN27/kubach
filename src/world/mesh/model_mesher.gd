class_name ModelMesher
extends RefCounted
## Модели из коробок вместо куба (станции, этап 6): поле model блока — коробки в 1/16
## блока, у каждой текстура другого блока (tex). Вершины в формате GreedyMesher (UV в блоках,
## ID блока-текстуры в UV2.x, нейтральный COLOR), поэтому идут в ту же секцию с тем же
## материалом и светом. Поворот модели (0…3 × 90° вокруг вертикали) — из данных станции.
## Коробки с anim (колёса) сюда не попадают — их крутит StationSystem отдельным мешем.
## Потокобезопасен: после создания только читает свои таблицы.

var _ids := PackedInt32Array()
## num блока → Array коробок [from: Vector3, to: Vector3, tex: int, anim: bool].
var _boxes := {}


func _init(registry: ContentRegistry) -> void:
	for b in range(1, registry.block_count()):
		var def := registry.block_by_num(b)
		if not def.has_model():
			continue
		_ids.append(b)
		var list := []
		for m: Dictionary in def.model:
			list.append([m["from"], m["to"], maxi(0, registry.block_num(m["tex"])), m["anim"] != &""])
		_boxes[b] = list


## Есть ли в секции блоки с моделью (быстро: поиск в упакованном массиве — на C++).
func any_in(center: Array) -> bool:
	if _ids.is_empty():
		return false
	var cb: PackedInt32Array = center[1]
	if cb.is_empty():
		return _boxes.has(int(center[0]))
	for id in _ids:
		if cb.has(id):
			return true
	return false


## Массивы меша (как у поверхности мешера) или пусто. facings: локальный индекс → 0…3.
func build(center: Array, facings: Dictionary) -> Array:
	var cb: PackedInt32Array = center[1]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for id in _ids:
		var from := cb.find(id) if not cb.is_empty() else (0 if int(center[0]) == id else -1)
		while from >= 0:
			var x := from & 15
			var z := (from >> 4) & 15
			var y := from >> 8
			var f := int(facings.get(from, 0))
			for box: Array in _boxes[id]:
				if box[3]:
					continue
				emit_box(Vector3(x, y, z), box[0], box[1], int(box[2]), f, verts, normals, colors, uvs, uv2s, indices)
			if cb.is_empty():
				break
			from = cb.find(id, from + 1)
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Повернуть точку модели (в блоке 0…1) на facing × 90° вокруг центра блока.
static func rotate_point(p: Vector3, facing: int) -> Vector3:
	var c := p - Vector3(0.5, 0.0, 0.5)
	for i in posmod(facing, 4):
		c = Vector3(-c.z, c.y, c.x)
	return c + Vector3(0.5, 0.0, 0.5)


static func rotate_normal(n: Vector3, facing: int) -> Vector3:
	var c := n
	for i in posmod(facing, 4):
		c = Vector3(-c.z, c.y, c.x)
	return c


## Шесть граней коробки from…to в блоке base (локальные координаты секции).
static func emit_box(base: Vector3, from: Vector3, to: Vector3, tex: int, facing: int, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		indices: PackedInt32Array) -> void:
	var a := from
	var b := to
	# Углы: x, y, z из a/b.
	var faces := [
		[Vector3.LEFT, [Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z)]],
		[Vector3.RIGHT, [Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z)]],
		[Vector3.DOWN, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]],
		[Vector3.UP, [Vector3(a.x, b.y, a.z), Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z)]],
		[Vector3.FORWARD, [Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z)]],
		[Vector3.BACK, [Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]],
	]
	for fc: Array in faces:
		var n := rotate_normal(fc[0], facing)
		var pts: Array = fc[1]
		var base_i := verts.size()
		var p := PackedVector3Array()
		for k in 4:
			p.append(base + rotate_point(pts[k], facing))
		# UV — по мировым осям грани в блоках (как у мешера): верх/низ — (x, z), бока — (u, y).
		var uv_axes := Vector2i(0, 2) if absf(n.y) > 0.5 else (Vector2i(2, 1) if absf(n.x) > 0.5 else Vector2i(0, 1))
		for k in 4:
			verts.append(p[k])
			normals.append(n)
			colors.append(GreedyMesher.NEUTRAL)
			uvs.append(Vector2(p[k][uv_axes.x], p[k][uv_axes.y]))
			uv2s.append(Vector2(tex, 0.0))
		var flip := (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0
		if flip:
			indices.append_array([base_i, base_i + 2, base_i + 1, base_i, base_i + 3, base_i + 2])
		else:
			indices.append_array([base_i, base_i + 1, base_i + 2, base_i, base_i + 2, base_i + 3])


## Коробки с анимацией модели блока num: [[from, to, tex, anim], ...] (для StationSystem).
func anim_boxes(num: int, registry: ContentRegistry) -> Array:
	var out := []
	var def := registry.block_by_num(num)
	for m: Dictionary in def.model:
		if m["anim"] != &"":
			out.append([m["from"], m["to"], maxi(0, registry.block_num(m["tex"])), m["anim"]])
	return out
