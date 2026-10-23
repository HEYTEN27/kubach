extends RefCounted
## Генерация одной колонны 16×576×16 (в одном потоке). Бюджет — < 10 мс на 6-ядерном CPU.

var name := "terrain_column"
var iterations := 40
var _gen: TerrainGenerator
var _i := 0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_gen = TerrainGenerator.new(777, reg)


func run() -> void:
	_gen.generate_column(Vector2i(_i * 3, -_i * 5))
	_i += 1


func teardown() -> void:
	pass
