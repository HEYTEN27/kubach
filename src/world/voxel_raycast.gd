class_name VoxelRaycast
extends RefCounted
## Луч по сетке блоков (алгоритм Amanatides–Woo / DDA). Начало луча — в мировых double-координатах,
## поэтому точность одинакова и у центра мира, и на ±15 000.


## `is_target(x, y, z) -> bool`. Результат: { hit, block: Vector3i, normal: Vector3i, distance }.
## normal — грань, через которую луч вошёл в блок (куда ставить новый блок).
static func cast(ox: float, oy: float, oz: float, dir: Vector3, max_distance: float, is_target: Callable) -> Dictionary:
	var miss := { "hit": false, "block": Vector3i.ZERO, "normal": Vector3i.ZERO, "distance": max_distance }
	if dir.is_zero_approx():
		return miss
	var d := dir.normalized()
	var o := [ox, oy, oz]
	var cell := [floori(ox), floori(oy), floori(oz)]
	var step := [0, 0, 0]
	var t_max := [INF, INF, INF]
	var t_delta := [INF, INF, INF]
	for a in 3:
		var da: float = d[a]
		if da > 0.0:
			step[a] = 1
			t_delta[a] = 1.0 / da
			t_max[a] = (float(cell[a]) + 1.0 - o[a]) * t_delta[a]
		elif da < 0.0:
			step[a] = -1
			t_delta[a] = -1.0 / da
			t_max[a] = (o[a] - float(cell[a])) * t_delta[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance:
		if is_target.call(cell[0], cell[1], cell[2]):
			return { "hit": true, "block": Vector3i(cell[0], cell[1], cell[2]), "normal": normal, "distance": t }
		var axis := 0
		if t_max[1] < t_max[axis]:
			axis = 1
		if t_max[2] < t_max[axis]:
			axis = 2
		t = t_max[axis]
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return miss
