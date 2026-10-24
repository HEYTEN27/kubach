extends RefCounted
## Свет колонны (NativeLight, C++) по области 3×3 сгенерированных колонн: небо и блоки.
## Считается в WorkerThreadPool; бюджет — < 10 мс на колонну в одном потоке.

var name := "light_column_native"
var iterations := 12
var _light: Object
var _areas: Array = []
var _i := 0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	var gen := TerrainGenerator.new(777, reg)
	_light = VoxelLight.create_best(reg)
	for n in 2:
		var area := []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var col := gen.generate_column(Vector2i(n * 9 + dx, n * 5 + dz))
				var snaps := []
				snaps.resize(WorldConst.SECTIONS_PER_COLUMN)
				for si in WorldConst.SECTIONS_PER_COLUMN:
					if col.sections[si] != null:
						snaps[si] = GreedyMesher.snapshot(col.sections[si])
				area.append(snaps)
		_areas.append(area)


func run() -> void:
	_light.light_column(_areas[_i % _areas.size()])
	_i += 1


func teardown() -> void:
	pass
