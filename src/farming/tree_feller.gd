class_name TreeFeller
extends RefCounted
## Срубленное дерево (этап 9, раздел 8 ТЗ): когда топор ломает бревно, бревна того же вида,
## связанные с ним (26 соседей) и не опирающиеся ни на что твёрдое, и листва их кроны падают
## целиком. Дома из брёвен на фундаменте не рушатся: бревно, стоящее на твёрдом блоке не из
## дерева, «держит» всю связку.

const MAX_LOGS := 400
const MAX_LEAVES := 2400
## Насколько далеко (шагов по листве, 26 соседей) от брёвен листва считается кроной.
const LEAF_STEPS := 6
## Смещения 26 соседей (крона с «дырами» связна по диагоналям).
static var NEIGHBORS_26: Array[Vector3i] = _make_neighbors()

## Найденное: { Vector3i → блок } брёвен и листвы. Пусто — дерево стоит.
var blocks := {}
var logs := 0
var leaves := 0


## Собрать падающее дерево после поломки бревна log_block в клетке p (уже воздух).
## leaf_ids — блоки листвы этого вида (пусто — любая листва).
func collect(world: World, p: Vector3i, log_block: int, leaf_ids: PackedInt32Array) -> bool:
	blocks.clear()
	logs = 0
	leaves = 0
	var reg := world.registry
	var seen := {}
	var queue: Array[Vector3i] = []
	for dy in range(0, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector3i(dx, dy, dz)
				if q != p and world.get_block(q.x, q.y, q.z) == log_block:
					queue.append(q)
					seen[q] = true
	if queue.is_empty():
		return false
	var log_set := {}
	while not queue.is_empty():
		var q: Vector3i = queue.pop_back()
		log_set[q] = true
		if log_set.size() > MAX_LOGS:
			return false
		# Опора: под бревном твёрдый блок не из этой связки и не листва — дерево стоит.
		var below := world.get_block(q.x, q.y - 1, q.z)
		if below < 0:
			return false
		if below != log_block and below != 0 and reg.block_solid[below] == 1 \
				and reg.block_render[below] != BlockDef.RENDER_CUTOUT:
			return false
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var n := q + Vector3i(dx, dy, dz)
					if seen.has(n) or n == p:
						continue
					seen[n] = true
					if world.get_block(n.x, n.y, n.z) == log_block:
						queue.append(n)
	for q: Vector3i in log_set:
		blocks[q] = log_block
	logs = log_set.size()
	# Крона: листва вокруг брёвен в пределах LEAF_STEPS шагов по листве.
	var front: Array[Vector3i] = []
	for q: Vector3i in log_set:
		front.append(q)
	var visited := {}
	for step in LEAF_STEPS:
		var next: Array[Vector3i] = []
		for q: Vector3i in front:
			for d: Vector3i in NEIGHBORS_26:
				var n := q + d
				if visited.has(n) or blocks.has(n):
					continue
				visited[n] = true
				var b := world.get_block(n.x, n.y, n.z)
				if b <= 0 or not _is_leaf(reg, b, leaf_ids):
					continue
				blocks[n] = b
				leaves += 1
				next.append(n)
				if leaves >= MAX_LEAVES:
					return true
		front = next
	return true


static func _make_neighbors() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx != 0 or dy != 0 or dz != 0:
					out.append(Vector3i(dx, dy, dz))
	return out


static func _is_leaf(reg: ContentRegistry, b: int, leaf_ids: PackedInt32Array) -> bool:
	if not leaf_ids.is_empty():
		return leaf_ids.has(b)
	var def := reg.block_by_num(b)
	return def != null and def.material == &"leaves"


## Изменения «всё в воздух» для World.apply_changes.
func clear_changes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for q: Vector3i in blocks:
		out.append_array([q.x, q.y, q.z, 0])
	return out


## Мировой угол рамки и её размер.
func bounds() -> AABB:
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := -lo
	for q: Vector3i in blocks:
		lo = Vector3i(mini(lo.x, q.x), mini(lo.y, q.y), mini(lo.z, q.z))
		hi = Vector3i(maxi(hi.x, q.x), maxi(hi.y, q.y), maxi(hi.z, q.z))
	return AABB(Vector3(lo), Vector3(hi - lo + Vector3i.ONE))
