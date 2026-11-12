class_name WorldTreeWriter
extends ColumnWriter
## Запись дерева из TreeBuilder в живой мир (выросший саженец): читает блоки из World, копит
## изменения и отдаёт их пакетом для World.apply_changes. Незагруженные клетки пропускаются
## (get_block = −1 — place_log/place_soft туда не пишут).

var world: World
var _changes := {}   # Vector3i → блок


func _init(p_world: World, at: Vector3i) -> void:
	super(ChunkColumn.new(Vector2i((at.x >> 4), (at.z >> 4))), p_world.registry)
	world = p_world
	# Рамка для отсечения крон в TreeBuilder: дерево целиком «внутри».
	x0 = at.x - 8
	z0 = at.z - 8


func inside(_x: int, _z: int) -> bool:
	return true


func get_block(x: int, y: int, z: int) -> int:
	var p := Vector3i(x, y, z)
	if _changes.has(p):
		return _changes[p]
	return world.get_block(x, y, z)


func set_block(x: int, y: int, z: int, block: int) -> void:
	if y < WorldConst.MIN_Y or y >= WorldConst.MAX_Y:
		return
	_changes[Vector3i(x, y, z)] = block


## Изменения для World.apply_changes: [x, y, z, блок]….
func changes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for p: Vector3i in _changes:
		out.append_array([p.x, p.y, p.z, _changes[p]])
	return out


func count() -> int:
	return _changes.size()
