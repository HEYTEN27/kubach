class_name StationSystem
extends Node
## Станции в мире (этап 6): живые объекты Station для станций в загруженных колоннах.
## Раз в TICK_SEC досчитывает их до игрового времени (GameClock), записывает состояние в
## данные блока (ChunkColumn.block_entities) — колонна сохраняется вместе со станциями, а при
## загрузке станция досчитывает, сколько прошло (дубление, плавка идут без игрока).
## Вблизи игрока показывает работу: огонь и дым частицами, свет OmniLight, вращение колёс
## (коробки модели с anim), искры у наковальни и точила.

## Станция закончила задание (для звука и подсказки).
signal job_done(pos: Vector3i, recipe: StringName)

const TICK_SEC := 0.25
const VISUAL_RADIUS := 48.0
const WATER_RADIUS := 2
const PARTICLES := "res://assets/textures/generated/particles/"

var world: World
var data: CraftingData
var clock: GameClock
## Где игрок (мировые координаты) — для частиц и света рядом.
var viewer := Vector3.ZERO
## Авто-режим мини-игр (настройка «Мини-игры» выключена).
var auto := false
## Частицы: 0 — выкл., 1 — мало, 2 — много (настройка «Частицы»).
var particles_level := 2
## Vector3i → Station.
var stations := {}

var _tick_left := 0.0
var _visuals := {}       # Vector3i → _Visual
var _water_cache := {}   # Vector3i → [bool, время проверки]
var _anim_mesher_boxes := {}   # num блока → коробки anim


func setup(p_world: World, p_data: CraftingData, p_clock: GameClock) -> void:
	world = p_world
	data = p_data
	clock = p_clock
	world.entity_flush = flush
	world.entity_removed.connect(_on_removed)
	world.block_changed.connect(_on_block_changed)
	world.chunks.column_loaded.connect(_on_column_loaded)
	world.chunks.column_unloading.connect(_on_column_unloading)
	for cpos: Vector2i in world.chunks.columns:
		_on_column_loaded(cpos)


## Абсолютное игровое время в минутах.
func now() -> float:
	return float(clock.day - 1) * GameClock.MINUTES_PER_DAY + clock.minute


func get_station(p: Vector3i) -> Station:
	return stations.get(p)


## Живая станция в клетке (создаётся, если блок — станция, а объекта ещё нет).
func station_at(p: Vector3i) -> Station:
	if stations.has(p):
		return stations[p]
	var b := world.get_block(p.x, p.y, p.z)
	var def := world.registry.block_by_num(b) if b > 0 else null
	if def == null or not def.is_station():
		return null
	var e := world.get_entity(p)
	if e.is_empty():
		e = { "type": "station", "kind": String(def.station_kind), "tier": def.station_tier, "facing": 0 }
		world.set_entity(p, e)
	return _make(p, e)


func _make(p: Vector3i, e: Dictionary) -> Station:
	var st := Station.new(data, StringName(e.get("kind", "")), int(e.get("tier", 1)))
	if st.def.is_empty():
		return null
	st.from_dict(e)
	st.auto = auto
	stations[p] = st
	# Досчёт времени, пока колонна была выгружена.
	st.advance_to(now(), { "water": has_water(p) })
	return st


## Записать состояние станции в данные блока.
func flush(p: Vector3i) -> void:
	var st: Station = stations.get(p)
	if st != null:
		world.set_entity(p, st.to_dict())


func flush_all() -> void:
	for p: Vector3i in stations:
		flush(p)


func set_auto(on: bool) -> void:
	auto = on
	for p: Vector3i in stations:
		(stations[p] as Station).auto = on


func _on_column_loaded(cpos: Vector2i) -> void:
	var col: ChunkColumn = world.chunks.columns.get(cpos)
	if col == null:
		return
	for k: int in col.block_entities:
		var e: Dictionary = col.block_entities[k]
		if String(e.get("type", "")) != "station":
			continue
		var lp := ChunkColumn.entity_pos(k)
		var p := Vector3i(cpos.x * 16 + lp.x, lp.y, cpos.y * 16 + lp.z)
		if not stations.has(p):
			_make(p, e)


func _on_column_unloading(cpos: Vector2i) -> void:
	for p: Vector3i in stations.keys():
		if Vector2i(p.x >> 4, p.z >> 4) == cpos:
			flush(p)
			stations.erase(p)
			_drop_visual(p)


func _on_removed(p: Vector3i) -> void:
	stations.erase(p)
	_drop_visual(p)


func _on_block_changed(p: Vector3i, _old: int, _new: int) -> void:
	# Новая станция: данные блока пишутся сразу после set_block — подхватываем в конце кадра.
	_pick_up.call_deferred(p)


func _pick_up(p: Vector3i) -> void:
	if stations.has(p):
		return
	var e := world.get_entity(p)
	if String(e.get("type", "")) == "station":
		_make(p, e)


## Есть ли вода в 2 блоках (промывочный лоток). Кэш на 2 с.
func has_water(p: Vector3i) -> bool:
	var c: Variant = _water_cache.get(p)
	var t := Time.get_ticks_msec()
	if c != null and t - int(c[1]) < 2000:
		return c[0]
	var found := false
	for dy in range(-1, 2):
		for dz in range(-WATER_RADIUS, WATER_RADIUS + 1):
			for dx in range(-WATER_RADIUS, WATER_RADIUS + 1):
				if not found and world.is_fluid(p.x + dx, p.y + dy, p.z + dz):
					var b := world.get_block(p.x + dx, p.y + dy, p.z + dz)
					found = world.registry.block_heat[b] <= 0.0
	_water_cache[p] = [found, t]
	return found


## Горит ли рядом печь, горн или плавильня с жаром не ниже temp (ковка на наковальне).
func heat_near(p: Vector3i, radius: int, temp: float) -> bool:
	for q: Vector3i in stations:
		var st: Station = stations[q]
		if not bool(st.def.get("heat_source", false)):
			continue
		if absi(q.x - p.x) <= radius and absi(q.y - p.y) <= radius and absi(q.z - p.z) <= radius and st.temp >= temp:
			return true
	return false


## Тепло горящих станций: [[x, y, z, тепло], ...] — для EnvironmentProbe.
func heat_sources() -> Array:
	var out := []
	for p: Vector3i in stations:
		var w := (stations[p] as Station).warmth()
		if w > 0.0:
			out.append([p.x, p.y, p.z, w])
	return out


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_SEC
	var t := now()
	for p: Vector3i in stations.keys():
		var st: Station = stations[p]
		var events := st.advance_to(t, { "water": has_water(p) if bool(st.def.get("needs_water", false)) else true })
		flush(p)
		for ev: Dictionary in events:
			job_done.emit(p, StringName(ev.get("recipe", "")))
			_play(p, "crafting/done")
		_update_visual(p, st)


func _play(p: Vector3i, key: String) -> void:
	if world.is_inside_tree():
		var audio := get_node_or_null(^"/root/Audio")
		if audio != null:
			audio.play_at(key, world.to_scene(p.x + 0.5, p.y + 0.6, p.z + 0.5))


# --- видимость работы ---------------------------------------------------------------------

func _update_visual(p: Vector3i, st: Station) -> void:
	var near := Vector3(p.x + 0.5, p.y + 0.5, p.z + 0.5).distance_to(viewer) < VISUAL_RADIUS
	var working: bool = not st.job.is_empty() and not st.job.get("done", false) and st.blocker({ "water": true }) == ""
	var lit := st.lit()
	var has_anim := _anim_boxes(p).size() > 0
	if not near or (not lit and not working and not has_anim):
		_drop_visual(p)
		return
	var v: _Visual = _visuals.get(p)
	if v == null:
		v = _Visual.new()
		v.setup(self, p, st)
		world.add_child(v)
		_visuals[p] = v
	v.set_state(lit, working, particles_level)


func _drop_visual(p: Vector3i) -> void:
	var v: Node = _visuals.get(p)
	if v != null:
		v.queue_free()
		_visuals.erase(p)


func _anim_boxes(p: Vector3i) -> Array:
	var b := world.get_block(p.x, p.y, p.z)
	if b <= 0:
		return []
	if not _anim_mesher_boxes.has(b):
		var out := []
		for m: Dictionary in world.registry.block_by_num(b).model:
			if m["anim"] != &"":
				out.append([m["from"], m["to"], maxi(0, world.registry.block_num(m["tex"])), m["anim"]])
		_anim_mesher_boxes[b] = out
	return _anim_mesher_boxes[b]


## Огонь, дым, искры, свет и вращающиеся части одной станции (узел в координатах мира).
class _Visual:
	extends Node3D
	var system: StationSystem
	var fire: CPUParticles3D
	var smoke: CPUParticles3D
	var sparks: CPUParticles3D
	var light: OmniLight3D
	var spinners: Array[Node3D] = []
	var spin_axes: Array[Vector3] = []
	var working := false
	var _t := 0.0

	func setup(sys: StationSystem, p: Vector3i, st: Station) -> void:
		system = sys
		position = Vector3(p.x, p.y, p.z)
		var effects: Array = st.def.get("effects", [])
		var facing := st.facing
		# Огонь у «рта» печи (перед модели), у костра — в центре.
		var mouth := ModelMesher.rotate_point(Vector3(0.5, 0.25, 0.12), facing)
		if st.kind == &"campfire":
			mouth = Vector3(0.5, 0.15, 0.5)
		if effects.has("fire"):
			fire = _emitter("flame", mouth, 24, 0.6, Vector3(0, 1.2, 0), 0.16, Color(1, 0.8, 0.5), true)
			add_child(fire)
		if effects.has("smoke"):
			var top := Vector3(0.5, 1.1, 0.5) if st.kind != &"campfire" else Vector3(0.5, 0.6, 0.5)
			if st.kind == &"furnace":
				top = Vector3(0.5, 1.3, 0.5)
			smoke = _emitter("smoke", top, 10, 3.0, Vector3(0, 0.9, 0), 0.35, Color(0.6, 0.6, 0.6, 0.6), false)
			add_child(smoke)
		if effects.has("sparks"):
			sparks = _emitter("spark", Vector3(0.5, 1.0, 0.5), 12, 0.5, Vector3(0, 2.5, 0), 0.05, Color(1, 0.8, 0.4), true)
			sparks.spread = 70.0
			sparks.gravity = Vector3(0, -6, 0)
			add_child(sparks)
		var lvl := int(st.def.get("light", 0))
		if lvl > 0:
			light = OmniLight3D.new()
			light.light_color = st.def.get("light_color", Color(1, 0.7, 0.4))
			light.omni_range = lvl * 0.6
			light.position = mouth + Vector3(0, 0.3, 0)
			light.shadow_enabled = false
			add_child(light)
		var mat := system.world.chunks.materials.for_const(&"opaque", Color(1, 0, 0, 0))
		for box: Array in system._anim_boxes(p):
			var from: Vector3 = box[0]
			var to: Vector3 = box[1]
			var pivot := ModelMesher.rotate_point((from + to) * 0.5, facing)
			var holder := Node3D.new()
			holder.position = pivot
			add_child(holder)
			var arrays := _box_arrays(from, to, int(box[2]), facing, pivot)
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			holder.add_child(mi)
			spinners.append(holder)
			var axis := { &"spin_x": Vector3.RIGHT, &"spin_y": Vector3.UP, &"spin_z": Vector3.BACK }.get(box[3], Vector3.UP) as Vector3
			spin_axes.append(ModelMesher.rotate_normal(axis, facing))

	static func _box_arrays(from: Vector3, to: Vector3, tex: int, facing: int, pivot: Vector3) -> Array:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var idx := PackedInt32Array()
		ModelMesher.emit_box(-pivot, from, to, tex, facing, verts, normals, colors, uvs, uv2s, idx)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = idx
		return arrays

	func _emitter(tex_name: String, pos: Vector3, amount: int, life: float, vel: Vector3, size: float, col: Color,
			glow: bool) -> CPUParticles3D:
		var e := CPUParticles3D.new()
		e.position = pos
		e.amount = amount
		e.lifetime = life
		e.direction = vel.normalized()
		e.spread = 18.0
		e.initial_velocity_min = vel.length() * 0.6
		e.initial_velocity_max = vel.length()
		e.gravity = Vector3.ZERO
		e.scale_amount_min = 0.7
		e.scale_amount_max = 1.3
		e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		e.emission_sphere_radius = 0.12
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size) * 2.0
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if glow else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.vertex_color_use_as_albedo = true
		var path := PARTICLES + tex_name + ".png"
		if ResourceLoader.exists(path):
			m.albedo_texture = load(path)
		if glow:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 2.5
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		quad.material = m
		e.mesh = quad
		var grad := Gradient.new()
		grad.set_color(0, Color(col, col.a))
		grad.set_color(1, Color(col, 0.0))
		e.color_ramp = grad
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.6))
		curve.add_point(Vector2(1, 1.4 if not glow else 0.3))
		e.scale_amount_curve = curve
		e.emitting = false
		return e

	func set_state(lit: bool, p_working: bool, level: int) -> void:
		working = p_working
		var on := level > 0
		if fire != null:
			fire.emitting = lit and on
			fire.amount = 12 if level == 1 else 24
		if smoke != null:
			smoke.emitting = lit and on
		if sparks != null:
			sparks.emitting = working and on and level >= 1
		if light != null:
			light.visible = lit

	func _process(delta: float) -> void:
		_t += delta
		if light != null and light.visible:
			# Мерцание пламени.
			light.light_energy = 1.1 + 0.25 * sin(_t * 9.0) + 0.15 * sin(_t * 23.0 + 1.3)
		if working:
			for i in spinners.size():
				spinners[i].rotate(spin_axes[i], delta * 4.0)
