extends RefCounted
## Greedy-мешинг секции с поверхностью рельефа (худший типичный случай) вместе с соседями.
## Бюджет — < 2 мс на 6-ядерном CPU в одном потоке.

var name := "mesh_surface_section"
var iterations := 30
var _mesher: GreedyMesher
var _jobs: Array = []
var _i := 0


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	var gen := TerrainGenerator.new(777, reg)
	_mesher = GreedyMesher.new(reg)
	for n in 6:
		var cpos := Vector2i(n * 7, n * 3)
		var cols := {}
		for d: Vector2i in [Vector2i.ZERO, Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			cols[d] = gen.generate_column(cpos + d)
		var center: ChunkColumn = cols[Vector2i.ZERO]
		# Самая «смешанная» секция колонны — с поверхностью.
		var si := WorldConst.section_index(center.top_block_y(8, 8))
		_jobs.append([
			GreedyMesher.snapshot(center.sections[si]),
			[
				GreedyMesher.snapshot(cols[Vector2i(-1, 0)].sections[si]),
				GreedyMesher.snapshot(cols[Vector2i(1, 0)].sections[si]),
				GreedyMesher.snapshot(center.sections[si - 1]),
				GreedyMesher.snapshot(center.sections[si + 1]),
				GreedyMesher.snapshot(cols[Vector2i(0, -1)].sections[si]),
				GreedyMesher.snapshot(cols[Vector2i(0, 1)].sections[si]),
			],
		])


func run() -> void:
	var job: Array = _jobs[_i % _jobs.size()]
	_mesher.mesh_section(job[0], job[1])
	_i += 1


func teardown() -> void:
	pass
