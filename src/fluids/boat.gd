class_name Boat
extends Node3D
## Лодка или плот (этап 8, раздел 10 ТЗ). Тело — VoxelBody (AABB по ширине корпуса, координаты в
## double); на воде держится у поверхности (осадка DRAFT), качается на волне, течение сносит;
## на суше почти не едет. Гребёт тот, кто сидит: W/S — вперёд/назад, A/D — поворот. Модель —
## коробки с текстурой блока из data (texture_block): доски у лодки, брёвна у плота.

const DRAFT := 0.22
const ACCEL := 3.0
const WATER_DRAG := 0.9
const LAND_DRAG := 6.0
const GRAVITY := 24.0

var world: World
var item: StringName
var def := {}
var body: VoxelBody
var yaw := 0.0
var speed := 0.0
var vy := 0.0
var hits_left := 3
var rider: Player
var in_water := false
## Течение: `current_at(x, y, z) -> Vector3`.
var current_at: Callable
var _t := 0.0


## tex — текстура корпуса (VehicleSystem достаёт слой атласа), null — просто цвет.
func setup(p_world: World, p_item: StringName, x: float, y: float, z: float, p_yaw: float, tex: Texture2D = null) -> void:
	world = p_world
	item = p_item
	var d := world.registry.item(item)
	def = d.vehicle if d != null else {}
	hits_left = int(def.get("hits", 3))
	body = VoxelBody.new(world.is_solid)
	body.half_width = minf(float(def.get("width", 1.3)), float(def.get("length", 2.6))) * 0.5 - 0.05
	body.height = 0.6
	body.set_position(x, y, z)
	yaw = p_yaw
	_build_model(tex)


## Шаг физики: forward −1…1 (гребля), turn −1…1 (влево/вправо).
func step(dt: float, forward: float, turn: float) -> void:
	_t += dt
	var s := world.liquid_surface(body.x, body.y + 0.05, body.z)
	if s == -INF:
		s = world.liquid_surface(body.x, body.y - 0.3, body.z)
	in_water = s != -INF
	var max_speed := float(def.get("speed", 5.0))
	if in_water:
		var target := s - DRAFT
		vy = lerpf(vy, clampf((target - body.y) * 5.0, -3.0, 3.0), 1.0 - exp(-6.0 * dt))
		speed = move_toward(speed, forward * max_speed, ACCEL * dt) if absf(forward) > 0.01 else speed * exp(-WATER_DRAG * dt)
		yaw = wrapf(yaw - turn * float(def.get("turn", 1.6)) * dt * (0.4 + 0.6 * minf(1.0, absf(speed) / 2.0 + 0.5)), -PI, PI)
	else:
		vy = maxf(vy - GRAVITY * dt, -30.0)
		speed *= exp(-LAND_DRAG * dt)
		yaw = wrapf(yaw - turn * 0.4 * dt, -PI, PI)
	var dir := Vector2(-sin(yaw), -cos(yaw))
	var dx := dir.x * speed * dt
	var dz := dir.y * speed * dt
	if in_water and current_at.is_valid():
		var c: Vector3 = current_at.call(body.x, body.y + DRAFT, body.z)
		dx += c.x * dt
		dz += c.z * dt
	body.move(dx, vy * dt, dz)
	if body.moved_y != vy * dt:
		vy = 0.0
	if body.hit_wall:
		speed *= -0.25


## Место седока (мировые координаты ног).
func seat() -> PackedFloat64Array:
	return PackedFloat64Array([body.x, body.y + 0.2, body.z])


## Пересечение луча (мировые, double) с корпусом: расстояние или −1.
func ray_hit(ox: float, oy: float, oz: float, dir: Vector3, reach: float) -> float:
	var hw := body.half_width + 0.15
	var lo := Vector3(body.x - hw - ox, body.y - oy, body.z - hw - oz)
	var hi := Vector3(body.x + hw - ox, body.y + 0.7 - oy, body.z + hw - oz)
	var tmin := 0.0
	var tmax := reach
	for a in 3:
		if absf(dir[a]) < 1e-6:
			if 0.0 < lo[a] or 0.0 > hi[a]:
				return -1.0
			continue
		var t1 := lo[a] / dir[a]
		var t2 := hi[a] / dir[a]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
		if tmin > tmax:
			return -1.0
	return tmin


func to_dict() -> Dictionary:
	return { "item": String(item), "x": body.x, "y": body.y, "z": body.z, "yaw": yaw }


func _process(_delta: float) -> void:
	if world == null:
		return
	position = world.to_scene(body.x, body.y, body.z)
	var bob := sin(_t * 1.7) * 0.04 if in_water else 0.0
	rotation = Vector3(sin(_t * 1.3) * 0.03 if in_water else 0.0, yaw, bob)


## Модель из коробок с текстурой блока (боковая грань из атласа как обычная 2D-текстура).
func _build_model(tex: Texture2D) -> void:
	var length := float(def.get("length", 2.6))
	var width := float(def.get("width", 1.3))
	var mat := StandardMaterial3D.new()
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(1, 1, 1)
	mat.roughness = 0.85
	if tex != null:
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		mat.albedo_color = Color(0.55, 0.4, 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := length * 0.5
	var hw := width * 0.5
	if String(def.get("kind", "boat")) == "raft":
		var n := 5
		var lw := width / n
		for i in n:
			var x0 := -hw + i * lw + 0.02
			_box(st, Vector3(x0, 0.0, -hl), Vector3(x0 + lw - 0.04, 0.32, hl))
		_box(st, Vector3(-hw, 0.32, -hl * 0.7), Vector3(hw, 0.38, -hl * 0.7 + 0.18))
		_box(st, Vector3(-hw, 0.32, hl * 0.7 - 0.18), Vector3(hw, 0.38, hl * 0.7))
	else:
		_box(st, Vector3(-hw, 0.0, -hl), Vector3(hw, 0.08, hl))          # днище
		_box(st, Vector3(-hw, 0.08, -hl), Vector3(-hw + 0.08, 0.5, hl))  # борта
		_box(st, Vector3(hw - 0.08, 0.08, -hl), Vector3(hw, 0.5, hl))
		_box(st, Vector3(-hw, 0.08, -hl), Vector3(hw, 0.6, -hl + 0.1))   # нос выше
		_box(st, Vector3(-hw, 0.08, hl - 0.1), Vector3(hw, 0.45, hl))
		_box(st, Vector3(-hw, 0.3, -0.12), Vector3(hw, 0.36, 0.12))      # банка
		_box(st, Vector3(-hw - 0.5, 0.42, 0.05), Vector3(-hw + 0.1, 0.46, 0.13))  # вёсла
		_box(st, Vector3(hw - 0.1, 0.42, 0.05), Vector3(hw + 0.5, 0.46, 0.13))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _box(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var c := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	for f: Array in [[0, 3, 2, 1], [5, 6, 7, 4], [4, 7, 3, 0], [1, 2, 6, 5], [3, 7, 6, 2], [4, 0, 1, 5]]:
		for t: Array in [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]:
			for i: int in t:
				st.add_vertex(c[i])
