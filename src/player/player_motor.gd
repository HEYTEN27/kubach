class_name PlayerMotor
extends RefCounted
## Движение игрока поверх VoxelBody: ходьба, бег, присед (не падаешь с края), ровно один прыжок
## на 1,25 блока, плавание, полёт в творческом режиме. Без узлов и ввода — тестируется напрямую.
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
var vx := 0.0
var vy := 0.0
var vz := 0.0
var flying := false
var crouching := false
var sprinting := false
var in_fluid := false
## Высота последнего падения (в блоках), выставляется в шаге приземления, иначе 0.
var landed_fall := 0.0
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
	_update_crouch(crouch and not flying)
	sprinting = sprint and not crouching and wish.length_squared() > 0.01
	in_fluid = _check_fluid()
	if flying:
		_step_fly(dt, wish, jump, crouch)
		return

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif in_fluid:
		speed = SWIM_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	var accel := GROUND_ACCEL if body.on_ground or in_fluid else AIR_ACCEL
	vx = move_toward(vx, wish.x * speed, accel * dt)
	vz = move_toward(vz, wish.y * speed, accel * dt)

	var dy: float
	if in_fluid:
		# Упрощённое плавание (полноценное — этап 8): медленное погружение, всплытие на прыжок.
		vy = clampf(vy - GRAVITY * 0.15 * dt, -3.0, 3.0)
		if jump:
			vy = minf(vy + GRAVITY * 0.5 * dt, 2.6)
		vy *= 0.92
		dy = vy * dt
	else:
		if jump and body.on_ground:
			vy = JUMP_VELOCITY
		dy = vy * dt - 0.5 * GRAVITY * dt * dt
		vy = maxf(vy - GRAVITY * dt, -TERMINAL_VELOCITY)

	var dx := vx * dt
	var dz := vz * dt
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
	if not is_fluid.is_valid():
		return false
	return is_fluid.call(floori(body.x), floori(body.y + 0.4), floori(body.z))


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
