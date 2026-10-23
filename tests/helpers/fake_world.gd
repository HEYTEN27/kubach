class_name FakeWorld
extends RefCounted
## Мир для тестов физики: пол (y < floor_y) и отдельные блоки из словаря.

var floor_y := 0
var solid := {}
var fluid := {}


func is_solid(x: int, y: int, z: int) -> bool:
	return y < floor_y or solid.has(Vector3i(x, y, z))


func is_fluid(x: int, y: int, z: int) -> bool:
	return fluid.has(Vector3i(x, y, z))


func add_box(from: Vector3i, to: Vector3i) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			for z in range(from.z, to.z + 1):
				solid[Vector3i(x, y, z)] = true
