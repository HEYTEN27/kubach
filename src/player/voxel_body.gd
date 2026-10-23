class_name VoxelBody
extends RefCounted
## Ось-ориентированный прямоугольник (AABB), который двигается по сетке блоков.
## Координаты — double (float в GDScript): x, z — центр основания, y — низ (ступни).
## Сдвиг идёт по осям по очереди (Y, X, Z): так не застреваешь на стыках блоков
## и спокойно съезжаешь вдоль стены.

const EPS := 1e-7

var x := 0.0
var y := 0.0
var z := 0.0
var half_width := 0.3
var height := 1.8
var on_ground := false
var hit_wall := false
## Фактический сдвиг последнего move(). Не Vector3: тот хранит float32 и теряет точность на ±15 000.
var moved_x := 0.0
var moved_y := 0.0
var moved_z := 0.0
## `is_solid(bx: int, by: int, bz: int) -> bool` — непроходимый ли блок.
var is_solid: Callable


func _init(p_is_solid: Callable = Callable()) -> void:
	is_solid = p_is_solid


func set_position(px: float, py: float, pz: float) -> void:
	x = px
	y = py
	z = pz


## Пытается сдвинуться; фактический сдвиг — в moved_x/moved_y/moved_z.
func move(dx: float, dy: float, dz: float) -> void:
	var ry := _clip(1, dy)
	y += ry
	var rx := _clip(0, dx)
	x += rx
	var rz := _clip(2, dz)
	z += rz
	# Граница мира — невидимая стена.
	var lim := float(WorldConst.WORLD_HALF) - half_width
	var cx := clampf(x, -lim, lim)
	var cz := clampf(z, -lim, lim)
	rx += cx - x
	rz += cz - z
	x = cx
	z = cz
	on_ground = dy < 0.0 and ry > dy
	hit_wall = rx != dx or rz != dz
	moved_x = rx
	moved_y = ry
	moved_z = rz


## Пересекается ли тело с непроходимыми блоками (для проверки установки блока и т.п.).
func intersects_block(bx: int, by: int, bz: int) -> bool:
	return (x + half_width > bx + EPS and x - half_width < bx + 1 - EPS
		and y + height > by + EPS and y < by + 1 - EPS
		and z + half_width > bz + EPS and z - half_width < bz + 1 - EPS)


## Есть ли опора под телом, если поставить его в (px, pz) на текущей высоте.
func has_support_at(px: float, pz: float) -> bool:
	var by := floori(y - 0.05)
	for bx in range(floori(px - half_width + EPS), floori(px + half_width - EPS) + 1):
		for bz in range(floori(pz - half_width + EPS), floori(pz + half_width - EPS) + 1):
			if is_solid.call(bx, by, bz):
				return true
	return false


func _min(axis: int) -> float:
	match axis:
		0: return x - half_width
		1: return y
		_: return z - half_width


func _max(axis: int) -> float:
	match axis:
		0: return x + half_width
		1: return y + height
		_: return z + half_width


func _clip(axis: int, delta: float) -> float:
	if delta == 0.0:
		return 0.0
	var o1 := (axis + 1) % 3
	var o2 := (axis + 2) % 3
	var r1 := Vector2i(floori(_min(o1) + EPS), floori(_max(o1) - EPS))
	var r2 := Vector2i(floori(_min(o2) + EPS), floori(_max(o2) - EPS))
	var lo := _min(axis)
	var hi := _max(axis)
	var from: int
	var to: int
	if delta > 0.0:
		from = floori(hi - EPS)
		to = floori(hi + delta)
	else:
		from = floori(lo + delta)
		to = floori(lo + EPS)
	var cell := [0, 0, 0]
	for a in range(from, to + 1):
		cell[axis] = a
		for b in range(r1.x, r1.y + 1):
			cell[o1] = b
			for c in range(r2.x, r2.y + 1):
				cell[o2] = c
				if not is_solid.call(cell[0], cell[1], cell[2]):
					continue
				if delta > 0.0:
					var face := float(a)
					if face >= hi - EPS:
						delta = minf(delta, face - hi)
				else:
					var face := float(a + 1)
					if face <= lo + EPS:
						delta = maxf(delta, face - lo)
	return delta
