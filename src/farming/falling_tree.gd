class_name FallingTree
extends Node3D
## Падающее срубленное дерево (этап 9): блоки дерева мешатся тем же greedy-мешером во временные
## секции и поворачиваются вокруг основания ствола от игрока с ускорением; по окончании падения
## узел исчезает, а предметы высыпаются там, где легли блоки (сигнал landed).

signal landed(points: Array)   # [[Vector3 мировая точка, блок], …]

const DURATION := 1.7
const HOLD := 0.25
## Замедление анимации (скриншоты: дерево застаёт кадр в падении).
static var time_scale := 1.0
## С какого момента начинать анимацию (скриншоты: кадр посреди падения).
static var start_t := 0.0

var _blocks := {}
var _pivot := Vector3.ZERO
var _axis := Vector3.RIGHT
var _t := 0.0
var _done := false


## blocks — { Vector3i → блок }, pivot — мировая точка шарнира (низ ствола), dir — куда падать.
func setup(world: World, mesher: Object, blocks: Dictionary, pivot: Vector3, dir: Vector3, tints: PackedColorArray) -> void:
	_blocks = blocks
	_pivot = pivot
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		flat = Vector3.FORWARD
	_axis = Vector3.UP.cross(flat.normalized()).normalized()
	position = pivot
	_t = start_t
	basis = Basis(_axis, angle_at(_t))
	# Блоки — по временным секциям 16³ относительно угла рамки.
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for q: Vector3i in blocks:
		lo = Vector3i(mini(lo.x, q.x), mini(lo.y, q.y), mini(lo.z, q.z))
	var secs := {}
	for q: Vector3i in blocks:
		var r := q - lo
		var key := Vector3i(r.x >> 4, r.y >> 4, r.z >> 4)
		var arr: PackedInt32Array = secs.get(key, PackedInt32Array())
		if arr.is_empty():
			arr.resize(4096)
		arr[WorldConst.local_index(r.x & 15, r.y & 15, r.z & 15)] = blocks[q]
		secs[key] = arr
	var mats := world.chunks.materials
	var nbs := [null, null, null, null, null, null]
	for key: Vector3i in secs:
		var origin := lo + key * 16
		var res: Dictionary = mesher.mesh_section([0, secs[key], false, false], nbs, tints, world.chunks.season, origin)
		if int(res.get("quads", 0)) == 0:
			continue
		var mesh := ArrayMesh.new()
		for surf: StringName in BlockMaterials.SURFACES:
			var arrays: Array = res.get(surf, [])
			if arrays.is_empty():
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats.for_const(surf, VoxelLight.SKY_FULL))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(origin) - pivot
		add_child(mi)


## Угол падения (рад) в момент t: с ускорением, как падающий шест.
static func angle_at(t: float) -> float:
	var k := clampf(t / DURATION, 0.0, 1.0)
	return PI * 0.5 * k * k


## Куда ляжет точка p (мировая) при повороте на угол a вокруг оси через шарнир.
static func rotate_point(p: Vector3, pivot: Vector3, axis: Vector3, a: float) -> Vector3:
	return pivot + (p - pivot).rotated(axis, a)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta * time_scale
	basis = Basis(_axis, angle_at(_t))
	if _t >= DURATION + HOLD:
		_done = true
		var points := []
		for q: Vector3i in _blocks:
			points.append([rotate_point(Vector3(q) + Vector3(0.5, 0.5, 0.5), _pivot, _axis, PI * 0.5), _blocks[q]])
		landed.emit(points)
		queue_free()
