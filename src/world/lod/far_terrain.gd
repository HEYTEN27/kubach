class_name FarTerrain
extends Node3D
## Дальний рельеф — LOD за дальностью прорисовки (раздел 20 ТЗ).
##
## Плитки 64×64 блока строятся прямо из генератора (TerrainGenerator.height_at / biome_at —
## чистые функции, колонны не генерируются): сетка высот с шагом 2, 4 или 8 блоков по мере
## удаления (децимация 2×/4×/8×), цвет верхнего блока биома с сезонной травой, лес — цветом
## крон, крутые склоны — породой, вода — отдельной поверхностью. Пещер, деревьев и правок
## игрока в LOD нет: это силуэт и цвет ландшафта вдали.
##
## Внутри радиуса прорисованных чанков шейдер отбрасывает LOD (см. far_terrain.gdshader).

const TILE := 64
## Порог дальности (в блоках от игрока до центра плитки) для шагов 2 и 4; дальше — 8.
const STEP2_DIST := 288.0
const STEP4_DIST := 576.0
const SINK := 0.3
var max_in_flight := 2

var world: World
var enabled := true
## Дальность LOD в колоннах.
var lod_distance := 32
## Радиус настоящих чанков в блоках: внутри LOD не рисуется.
var clip_radius := 180.0

var _land_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _tiles := {}          # Vector2i -> [step, MeshInstance3D]
var _tasks := {}          # Vector2i -> [id, step]
var _results: Array = []
var _mutex := Mutex.new()
var _center := Vector2i(1 << 30, 0)
var _player := Vector2.ZERO
var _wanted: Array = []   # [tile, step], ближние первыми
var _season := 1
var _gen: TerrainGenerator
var _top_color := PackedColorArray()     # биом → цвет верхнего блока
var _cliff_color := PackedColorArray()
var _tinted := PackedFloat32Array()      # биом → доля цвета травы
var _snow := PackedByteArray()


func setup(p_world: World, season: int) -> void:
	world = p_world
	_gen = world.generator
	_season = season
	var shader := load("res://src/world/lod/far_terrain.gdshader") as Shader
	_land_mat = ShaderMaterial.new()
	_land_mat.shader = shader
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = shader
	_water_mat.set_shader_parameter(&"water", true)
	var reg := world.registry
	var bs := _gen.biomes
	for b in bs.count:
		var top := reg.block_by_num(bs.top[b])
		_top_color.append(top.map_color if top != null else Color(0.4, 0.5, 0.3))
		_tinted.append(top.tint_strength if top != null and top.tint == &"grass" else 0.0)
		var cliff := reg.block_by_num(bs.cliff[b])
		_cliff_color.append(cliff.map_color if cliff != null else Color(0.45, 0.45, 0.45))
		_snow.append(bs.snow_cover[b])


func configure(p_enabled: bool, p_lod_distance: int, p_clip_radius: float) -> void:
	var changed := p_enabled != enabled or p_lod_distance != lod_distance
	enabled = p_enabled and p_lod_distance > 0
	lod_distance = p_lod_distance
	clip_radius = p_clip_radius
	_land_mat.set_shader_parameter(&"clip_radius", clip_radius)
	_water_mat.set_shader_parameter(&"clip_radius", clip_radius)
	if changed:
		for t: Vector2i in _tiles.keys():
			_remove(t)
		_center = Vector2i(1 << 30, 0)


func _exit_tree() -> void:
	wait_all()


func wait_all() -> void:
	for item: Array in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(item[0])
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()


func tile_count() -> int:
	return _tiles.size()


func pending() -> int:
	return _tasks.size() + _wanted.size()


## Шаг сетки плитки по расстоянию её центра до игрока (0 — плитка не нужна).
func step_for(tile: Vector2i, px: float, pz: float) -> int:
	var cx := tile.x * TILE + TILE * 0.5
	var cz := tile.y * TILE + TILE * 0.5
	var d := Vector2(cx - px, cz - pz).length()
	var half := TILE * 0.7072
	if d - half > lod_distance * 16.0:
		return 0
	if d + half < clip_radius:
		return 0
	if d < STEP2_DIST:
		return 2
	if d < STEP4_DIST:
		return 4
	return 8


## Каждый кадр: позиция игрока в мировых блоках.
func update(px: float, pz: float) -> void:
	_collect()
	if not enabled:
		return
	_player = Vector2(px, pz)
	var c := Vector2(px - world.origin.x, pz - world.origin.z)
	_land_mat.set_shader_parameter(&"clip_center", c)
	_water_mat.set_shader_parameter(&"clip_center", c)
	var center := Vector2i(floori(px / TILE), floori(pz / TILE))
	if center != _center:
		_center = center
		_rebuild_wanted()
	while _tasks.size() < max_in_flight and not _wanted.is_empty():
		var w: Array = _wanted.pop_front()
		var t: Vector2i = w[0]
		var step: int = w[1]
		if _tasks.has(t):
			continue
		var have: Array = _tiles.get(t, [])
		if not have.is_empty() and have[0] == step:
			continue
		var id := WorkerThreadPool.add_task(_build.bind(t, step), false, "lod %s" % t)
		_tasks[t] = [id, step]


func _rebuild_wanted() -> void:
	_wanted.clear()
	var r := ceili(lod_distance * 16.0 / TILE) + 1
	var keep := {}
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := _center + Vector2i(dx, dz)
			var step := step_for(t, _player.x, _player.y)
			if step == 0:
				continue
			keep[t] = true
			var have: Array = _tiles.get(t, [])
			if have.is_empty() or have[0] != step:
				_wanted.append([t, step])
	for t: Vector2i in _tiles.keys():
		if not keep.has(t):
			_remove(t)
	var p := _player
	_wanted.sort_custom(func(a: Array, b: Array) -> bool:
		var ta: Vector2i = a[0]
		var tb: Vector2i = b[0]
		return (Vector2(ta) * TILE - p).length_squared() < (Vector2(tb) * TILE - p).length_squared())


## Поток: сетка плитки → массивы поверхностей суши и воды.
func _build(tile: Vector2i, step: int) -> void:
	var n := TILE / step + 1
	var x0 := tile.x * TILE
	var z0 := tile.y * TILE
	var hs := PackedFloat32Array()
	var wl := PackedInt32Array()
	var bio := PackedInt32Array()
	hs.resize(n * n)
	wl.resize(n * n)
	bio.resize(n * n)
	var ctxs := {}
	var k := PackedFloat32Array()
	k.resize(BiomeSource.KIND_COUNT)
	for j in n:
		for i in n:
			var x := x0 + i * step
			var z := z0 + j * step
			var cp := Vector2i(x >> 4, z >> 4)
			var ctx: TerrainGenerator.Context = ctxs.get(cp)
			if ctx == null:
				ctx = _gen.make_context(cp, false)
				ctxs[cp] = ctx
			var r := _gen.height_at(ctx, x, z, k)
			hs[i + j * n] = float(r.x)
			wl[i + j * n] = r.y
			bio[i + j * n] = _gen.biome_at(ctx, x, z)
	var land := sample_surface(hs, wl, bio, n, step)
	var water := _water_arrays(hs, wl, bio, n, step)
	_mutex.lock()
	_results.append([tile, step, land, water])
	_mutex.unlock()


## Сетка суши: вершины, нормали, цвета, индексы (публично — для тестов).
func sample_surface(hs: PackedFloat32Array, wl: PackedInt32Array, bio: PackedInt32Array, n: int, step: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var idx := PackedInt32Array()
	var bs := _gen.biomes
	for j in n:
		for i in n:
			var p := i + j * n
			var h := hs[p]
			verts.append(Vector3(i * step, h + 1.0 - SINK, j * step))
			var hl := hs[maxi(i - 1, 0) + j * n]
			var hr := hs[mini(i + 1, n - 1) + j * n]
			var hd := hs[i + maxi(j - 1, 0) * n]
			var hu := hs[i + mini(j + 1, n - 1) * n]
			var nrm := Vector3((hl - hr) / (2.0 * step), 1.0, (hd - hu) / (2.0 * step)).normalized()
			normals.append(nrm)
			var b := bio[p]
			var c := _top_color[b]
			if _tinted[b] > 0.0:
				c = c.lerp(bs.palette(b, _season, false), _tinted[b])
			var slope := maxf(absf(hl - hr), absf(hd - hu)) / (2.0 * step)
			if slope > 1.2:
				c = c.lerp(_cliff_color[b], clampf((slope - 1.2) * 2.0, 0.0, 1.0))
			elif _snow[b] == 1:
				c = c.lerp(Color(0.93, 0.95, 0.98), 0.85)
			if bs.tree_density[b] > 0.0 and wl[p] == TerrainGenerator.NO_WATER:
				var forest := clampf(bs.tree_density[b] / 7.0, 0.0, 0.75)
				c = c.lerp(bs.palette(b, _season, true) * 0.62, forest)
			colors.append(c)
	for j in n - 1:
		for i in n - 1:
			var a := i + j * n
			idx.append_array([a, a + 1, a + n + 1, a, a + n + 1, a + n])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


func _water_arrays(hs: PackedFloat32Array, wl: PackedInt32Array, bio: PackedInt32Array, n: int, step: int) -> Array:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var bs := _gen.biomes
	for j in n - 1:
		for i in n - 1:
			var p := i + j * n
			var level := wl[p]
			if level == TerrainGenerator.NO_WATER:
				continue
			var y := float(level) + 1.0 - SINK * 0.5
			var x := float(i * step)
			var z := float(j * step)
			var c: Color = bs.defs[bio[p]].get("water_color", Color(0.18, 0.36, 0.52))
			# Обход по часовой, если смотреть сверху (лицевая сторона Godot).
			for v in [Vector3(x, y, z), Vector3(x + step, y, z), Vector3(x + step, y, z + step),
					Vector3(x, y, z), Vector3(x + step, y, z + step), Vector3(x, y, z + step)]:
				verts.append(v)
				colors.append(c)
				normals.append(Vector3.UP)
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


func _collect() -> void:
	_mutex.lock()
	var fresh := _results
	_results = []
	_mutex.unlock()
	for r: Array in fresh:
		var t: Vector2i = r[0]
		var item: Array = _tasks.get(t, [])
		if not item.is_empty():
			WorkerThreadPool.wait_for_task_completion(item[0])
			_tasks.erase(t)
		var step: int = r[1]
		if not enabled or step_for(t, _player.x, _player.y) != step:
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r[2])
		mesh.surface_set_material(0, _land_mat)
		var water: Array = r[3]
		if not water.is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water)
			mesh.surface_set_material(1, _water_mat)
		_remove(t)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position = Vector3(t.x * TILE, 0, t.y * TILE)
		add_child(node)
		_tiles[t] = [step, node]


func _remove(t: Vector2i) -> void:
	var have: Array = _tiles.get(t, [])
	if not have.is_empty():
		(have[1] as Node).queue_free()
		_tiles.erase(t)
