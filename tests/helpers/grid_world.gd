class_name GridWorld
extends RefCounted
## Мир для тестов жидкостей: ниже floor_y — камень, выше — воздух, отдельные клетки — словарь.
## Клетки вне [lo, hi] по X/Z считаются незагруженными (−1).

var floor_y := 0
var stone := 1
var cells := {}
var lo := Vector2i(-64, -64)
var hi := Vector2i(64, 64)
var writes := 0


func _init(p_stone: int) -> void:
	stone = p_stone


func get_block(x: int, y: int, z: int) -> int:
	if x < lo.x or z < lo.y or x > hi.x or z > hi.y:
		return -1
	var p := Vector3i(x, y, z)
	if cells.has(p):
		return cells[p]
	return stone if y < floor_y else 0


func set_block(x: int, y: int, z: int, b: int) -> bool:
	if get_block(x, y, z) < 0:
		return false
	cells[Vector3i(x, y, z)] = b
	writes += 1
	return true


func fill(from: Vector3i, to: Vector3i, b: int) -> void:
	for y in range(from.y, to.y + 1):
		for z in range(from.z, to.z + 1):
			for x in range(from.x, to.x + 1):
				cells[Vector3i(x, y, z)] = b
