class_name GrassField
extends Node3D
## Плотная трава вокруг игрока (раздел 16 ТЗ): MultiMesh-пучки на верхних блоках дёрна.
## Пучки колонны считаются в WorkerThreadPool, главный поток только создаёт MultiMesh.
## Отключается настройкой dense_grass; радиус и плотность — grass_distance, grass_density.

const SPRITE_SET := "grass"
const TUFT_HEIGHT := 0.6
const TUFT_WIDTH := 0.75

var chunks: ChunkManager
var enabled := true
var radius := 3
var density := 4

var _registry: ContentRegistry
var _material: ShaderMaterial
var _mesh: ArrayMesh
var _grass_ok := PackedByteArray()   # блок → 1: на нём растёт трава
var _skip := PackedByteArray()       # блок → 1: сквозь него смотрим вниз (растения, листва)
var _leaves := PackedByteArray()
var _nodes := {}        # Vector2i -> MultiMeshInstance3D
var _built := {}        # Vector2i -> true: трава колонны построена (может быть пустой)
var _tasks := {}        # Vector2i -> id
var _dirty := {}        # Vector2i -> true: перестроить
var _results: Array = []
var _mutex := Mutex.new()
var _center := Vector2i(1 << 30, 0)
var _missing := 0


func setup(p_chunks: ChunkManager, textures: BlockTextures) -> void:
	chunks = p_chunks
	_registry = chunks.world.registry
	var n := _registry.block_count()
	_grass_ok.resize(n)
	_skip.resize(n)
	_leaves.resize(n)
	for num in range(1, n):
		var b := _registry.block_by_num(num)
		if b.tint == &"grass" and b.shape == &"cube" and b.render == &"opaque":
			_grass_ok[num] = 1
		if b.shape != &"cube" or b.render == &"cutout":
			_skip[num] = 1
		if b.material == &"leaves":
			_leaves[num] = 1
	_mesh = _make_tuft_mesh()
	_material = ShaderMaterial.new()
	_material.shader = load("res://src/world/render/grass.gdshader") as Shader
	_material.set_shader_parameter(&"albedo_tex", textures.albedo)
	var info := textures.set_info(SPRITE_SET)
	_material.set_shader_parameter(&"layer", float(info.get("first", 0)))
	var gb := _registry.block(&"grass")
	if gb != null:
		var c := gb.map_color
		_material.set_shader_parameter(&"sprite_color", Vector3(c.r, c.g, c.b))
	_mesh.surface_set_material(0, _material)
	EventBus.block_broken.connect(_on_block_changed)
	EventBus.block_placed.connect(_on_block_changed)


func configure(p_enabled: bool, p_radius: int, p_density: int) -> void:
	var changed := p_enabled != enabled or p_radius != radius or p_density != density
	enabled = p_enabled
	radius = p_radius
	density = p_density
	_material.set_shader_parameter(&"fade_start", (radius - 0.8) * 16.0)
	_material.set_shader_parameter(&"fade_end", (radius + 0.2) * 16.0)
	if changed:
		for c: Vector2i in _built.keys():
			_remove(c)
		_center = Vector2i(1 << 30, 0)


func _exit_tree() -> void:
	wait_all()


func wait_all() -> void:
	for id: int in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()


## Колонн в радиусе, где трава ещё строится или ждёт очереди.
func pending() -> int:
	return _tasks.size() + _missing


func instance_count() -> int:
	var n := 0
	for node: MultiMeshInstance3D in _nodes.values():
		n += node.multimesh.instance_count
	return n


func update(center: Vector2i) -> void:
	_collect()
	if not enabled:
		return
	if center != _center:
		_center = center
		for c: Vector2i in _built.keys():
			if not _in_range(c):
				_remove(c)
	var budget := 2
	_missing = 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dz)
			if not _in_range(c) or _tasks.has(c) or (_built.has(c) and not _dirty.has(c)):
				continue
			if not chunks.columns.has(c) or not chunks.is_column_meshed(c):
				continue
			if budget <= 0:
				_missing += 1
				continue
			_dirty.erase(c)
			var col: ChunkColumn = chunks.columns[c]
			_tasks[c] = WorkerThreadPool.add_task(_build.bind(c, col, chunks.season, density), false, "grass %s" % c)
			budget -= 1


func _in_range(c: Vector2i) -> bool:
	var d := c - _center
	return d.x * d.x + d.y * d.y <= radius * radius + radius


func _on_block_changed(pos: Vector3i, _block: int, _scene_pos: Vector3) -> void:
	var c := Vector2i(pos.x >> 4, pos.z >> 4)
	if _built.has(c):
		_dirty[c] = true


## Поток: transform (12 float) + цвет (4) + custom (4) на пучок.
func _build(c: Vector2i, col: ChunkColumn, season: int, dens: int) -> void:
	var buf := PackedFloat32Array()
	var count := 0
	var tints := col.tints
	var seed := c.x * 73856093 ^ c.y * 19349663
	for lz in 16:
		for lx in 16:
			var top := _surface(col, lx, lz)
			if top.is_empty():
				continue
			var y: int = top[0]
			var b: int = top[1]
			var sky: float = top[2]
			var base := _registry.block_color[b]
			var color := base
			if tints.size() == 200:
				color = base.lerp(_tint(tints, season, lx + 0.5, lz + 0.5), _registry.block_tint_strength[b])
			for k in dens:
				var h := GenRandom.hash3(seed, lx, lz, k, 91)
				var ox := GenRandom.unit(h)
				var oz := GenRandom.unit(GenRandom.mix(h))
				var rot := GenRandom.unit(GenRandom.mix(h + 1)) * TAU
				var sc := 0.7 + 0.6 * GenRandom.unit(GenRandom.mix(h + 2))
				var basis := Basis(Vector3.UP, rot).scaled(Vector3(sc, sc * (0.8 + 0.4 * GenRandom.unit(GenRandom.mix(h + 3))), sc))
				var tint := 0.88 + 0.24 * GenRandom.unit(GenRandom.mix(h + 4))
				buf.append_array([basis.x.x, basis.y.x, basis.z.x, lx + ox,
					basis.x.y, basis.y.y, basis.z.y, float(y + 1),
					basis.x.z, basis.y.z, basis.z.z, lz + oz,
					color.r * tint, color.g * tint, color.b * tint, 1.0,
					sky, 0.0, 0.0, 0.0])
				count += 1
	_mutex.lock()
	_results.append([c, buf, count])
	_mutex.unlock()


## [y, блок, свет неба] верхнего блока дёрна столба или [] — травы нет.
func _surface(col: ChunkColumn, lx: int, lz: int) -> Array:
	var under_leaves := false
	for si in range(WorldConst.SECTIONS_PER_COLUMN - 1, -1, -1):
		var s := col.sections[si]
		if s == null:
			continue
		for ly in range(15, -1, -1):
			var b := s.get_block(WorldConst.local_index(lx, ly, lz))
			if b == 0:
				continue
			if _skip[b] == 1:
				if _leaves[b] == 1:
					under_leaves = true
				continue
			if _grass_ok[b] == 1:
				return [WorldConst.section_base_y(si) + ly, b, 0.55 if under_leaves else 1.0]
			return []
	return []


static func _tint(tints: PackedColorArray, season: int, lx: float, lz: float) -> Color:
	var off := season * 2 * 25
	var gx := clampf(lx / 4.0, 0.0, 4.0)
	var gz := clampf(lz / 4.0, 0.0, 4.0)
	var ix := mini(int(gx), 3)
	var iz := mini(int(gz), 3)
	var c0 := tints[off + iz * 5 + ix].lerp(tints[off + iz * 5 + ix + 1], gx - ix)
	var c1 := tints[off + (iz + 1) * 5 + ix].lerp(tints[off + (iz + 1) * 5 + ix + 1], gx - ix)
	return c0.lerp(c1, gz - iz)


func _collect() -> void:
	_mutex.lock()
	var fresh := _results
	_results = []
	_mutex.unlock()
	for r: Array in fresh:
		var c: Vector2i = r[0]
		WorkerThreadPool.wait_for_task_completion(_tasks[c])
		_tasks.erase(c)
		if not enabled or not _in_range(c) or not chunks.columns.has(c):
			continue
		_remove(c)
		_built[c] = true
		var count: int = r[2]
		if count == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _mesh
		mm.instance_count = count
		mm.buffer = r[1]
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(c.x * 16, 0, c.y * 16)
		add_child(node)
		_nodes[c] = node


func _remove(c: Vector2i) -> void:
	_built.erase(c)
	var node: MultiMeshInstance3D = _nodes.get(c)
	if node != null:
		node.queue_free()
		_nodes.erase(c)


## Пучок: два скрещённых спрайта, низ в начале координат.
func _make_tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var hw := TUFT_WIDTH * 0.5
	for q in 2:
		var a := q * PI * 0.5 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a)) * hw
		var base := verts.size()
		verts.append_array([-d, d, d + Vector3(0, TUFT_HEIGHT, 0), -d + Vector3(0, TUFT_HEIGHT, 0)])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		for i in 4:
			normals.append(Vector3.UP)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
