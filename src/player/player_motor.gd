class_name PlayerMotor
extends RefCounted
## Движение игрока поверх VoxelBody: ходьба, бег, присед (не падаешь с края), ровно один прыжок
## на 1,25 блока, плавание, полёт в творческом режиме. Без узлов и ввода — тестируется напрямую.
## Плавание (этап 8): плавучесть держит голову над водой, прыжок — вверх (у стенки — выбраться
## на берег), присед — нырнуть; вход в воду гасит скорость падения; течение сносит; по мелководью
## идёшь медленнее.
## Шаг фиксированный (физический тик), интегрирование параболы точное — высота прыжка не зависит от FPS.

const GRAVITY := 32.0
const JUMP_HEIGHT := 1.25
## Начальная скорость прыжка из v² = 2gh.
static var JUMP_VELOCITY := sqrt(2.0 * GRAVITY * JUMP_HEIGHT)
const TERMINAL_VELOCITY := 60.0
const WALK_SPEED := 4.3
const SPRINT_SPEED := 5.6
const CROUCH_SPEED := 1.3
const SWIM_SPEED := 2.2
const SWIM_SPRINT_SPEED := 3.3
const SWIM_UP := 3.0
const DIVE_SPEED := 2.6
## Доля тела под водой, при которой игрок плывёт, и при которой плавучесть уравновешена.
const SWIM_DEPTH := 0.45
const FLOAT_DEPTH := 0.72
const FLY_SPEED := 10.9
const GROUND_ACCEL := 40.0
const AIR_ACCEL := 8.0
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.5
const STAND_EYE := 1.62
const CROUCH_EYE := 1.27

var body: VoxelBody
## `is_fluid(bx, by, bz) -> bool`.
var is_fluid: Callable
## Поверхность жидкости над точкой: `fluid_surface(x, y, z) -> float` (−INF — не в жидкости).
## Не задана — по is_fluid (полные блоки).
var fluid_surface: Callable
## Течение: `current_at(x, y, z) -> Vector3`, блоков/с.
var current_at: Callable
## Доля тела в жидкости 0…1.
var submerged := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var flying := false
var crouching := false
var sprinting := false
var in_fluid := false
## Высота последнего падения (в блоках), выставляется в шаге приземления, иначе 0.
var landed_fall := 0.0
## Был ли прыжок в последнем шаге (выносливость, этап 5).
var jumped := false
## Множитель скорости ходьбы (перегруз, позже — снег, болото, ранения).
var speed_mult := 1.0
var _fall_peak := 0.0
var _airborne := false


func _init(p_body: VoxelBody, p_is_fluid: Callable = Callable()) -> void:
	body = p_body
	is_fluid = p_is_fluid


func eye_height() -> float:
	return CROUCH_EYE if crouching else STAND_EYE


## wish — желаемое направление в мировых X/Z (длина ≤ 1).
func step(dt: float, wish: Vector2, jump: bool, sprint: bool, crouch: bool) -> void:
	landed_fall = 0.0
	jumped = false
	submerged = _submersion()
	in_fluid = submerged > SWIM_DEPTH
	_update_crouch(crouch and not flying and not in_fluid)
	sprinting = sprint and not crouching and wish.length_squared() > 0.01
	if flying:
		_step_fly(dt, wish, jump, crouch)
		return

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif in_fluid:
		speed = SWIM_SPRINT_SPEED if sprinting else SWIM_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	if not in_fluid and submerged > 0.0:
		speed *= 1.0 - 0.6 * submerged   # вброд
	speed *= speed_mult
	var accel := GROUND_ACCEL if body.on_ground or in_fluid else AIR_ACCEL
	vx = move_toward(vx, wish.x * speed, accel * dt)
	vz = move_toward(vz, wish.y * speed, accel * dt)

	var dy: float
	if in_fluid:
		var target_vy: float
		if jump and submerged < FLOAT_DEPTH + 0.15 and body.hit_wall:
			# У берега: выбраться прыжком.
			vy = JUMP_VELOCITY * 0.95
			target_vy = vy
			jumped = true
		elif jump:
			target_vy = SWIM_UP
		elif crouch:
			target_vy = -DIVE_SPEED
		else:
			# Плавучесть: держит на глубине FLOAT_DEPTH (голова над водой).
			target_vy = clampf((submerged - FLOAT_DEPTH) * 5.0, -1.2, 1.6)
		vy = lerpf(vy, target_vy, 1.0 - exp(-5.0 * dt))
		dy = vy * dt
	else:
		if jump and body.on_ground:
			vy = JUMP_VELOCITY
			jumped = true
		dy = vy * dt - 0.5 * GRAVITY * dt * dt
		vy = maxf(vy - GRAVITY * dt, -TERMINAL_VELOCITY)

	var dx := vx * dt
	var dz := vz * dt
	if submerged > 0.05 and current_at.is_valid():
		var cur: Vector3 = current_at.call(body.x, body.y + 0.2, body.z)
		var k := minf(1.0, submerged * 1.6)
		dx += cur.x * k * dt
		dz += cur.z * k * dt
		if in_fluid:
			dy += cur.y * 0.5 * k * dt
	if crouching and body.on_ground:
		if dx != 0.0 and not body.has_support_at(body.x + dx, body.z):
			dx = 0.0
			vx = 0.0
		if dz != 0.0 and not body.has_support_at(body.x + dx, body.z + dz):
			dz = 0.0
			vz = 0.0

	body.move(dx, dy, dz)
	if body.moved_y != dy:
		vy = 0.0
	if body.moved_x != dx:
		vx = 0.0
	if body.moved_z != dz:
		vz = 0.0
	_track_fall()


func _step_fly(dt: float, wish: Vector2, up: bool, down: bool) -> void:
	var speed := FLY_SPEED * (2.0 if sprinting else 1.0)
	vx = move_toward(vx, wish.x * speed, GROUND_ACCEL * 2.0 * dt)
	vz = move_toward(vz, wish.y * speed, GROUND_ACCEL * 2.0 * dt)
	var target_vy := 0.0
	if up:
		target_vy = FLY_SPEED * 0.75
	elif down:
		target_vy = -FLY_SPEED * 0.75
	vy = move_toward(vy, target_vy, GROUND_ACCEL * 2.0 * dt)
	body.move(vx * dt, vy * dt, vz * dt)
	if body.on_ground:
		flying = false
	_airborne = false


func _update_crouch(want: bool) -> void:
	if want == crouching:
		return
	if want:
		crouching = true
		body.height = CROUCH_HEIGHT
		return
	# Встать можно, только если над головой свободно.
	body.height = STAND_HEIGHT
	for bx in range(floori(body.x - body.half_width + VoxelBody.EPS), floori(body.x + body.half_width - VoxelBody.EPS) + 1):
		for bz in range(floori(body.z - body.half_width + VoxelBody.EPS), floori(body.z + body.half_width - VoxelBody.EPS) + 1):
			for by in range(floori(body.y + VoxelBody.EPS), floori(body.y + STAND_HEIGHT - VoxelBody.EPS) + 1):
				if body.is_solid.call(bx, by, bz):
					body.height = CROUCH_HEIGHT
					return
	crouching = false


func _check_fluid() -> bool:
	return submerged > SWIM_DEPTH


## Доля тела в жидкости по поверхности над ногами.
func _submersion() -> float:
	var s := -INF
	if fluid_surface.is_valid():
		s = fluid_surface.call(body.x, body.y + 0.05, body.z)
	elif is_fluid.is_valid():
		var by := floori(body.y + 0.05)
		if is_fluid.call(floori(body.x), by, floori(body.z)):
			while by < floori(body.y) + 4 and is_fluid.call(floori(body.x), by + 1, floori(body.z)):
				by += 1
			s = float(by + 1)
	if s == -INF:
		return 0.0
	return clampf((s - body.y) / maxf(body.height, 0.5), 0.0, 1.0)


func _track_fall() -> void:
	if body.on_ground or in_fluid:
		if _airborne and not in_fluid:
			landed_fall = maxf(0.0, _fall_peak - body.y)
		_airborne = false
		return
	if not _airborne:
		_airborne = true
		_fall_peak = body.y
	else:
		_fall_peak = maxf(_fall_peak, body.y)
