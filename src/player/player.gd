class_name Player
extends Node3D
## Игрок: ввод, физика (PlayerMotor), камера 1-го и 3-го лица, модель, взаимодействие с блоками.
##
## Положение хранится в мировых double-координатах (body.x/y/z). Узел Player стоит в сценовых
## координатах (World.to_scene) с интерполяцией между физическими тиками.
## Камера: F5 переключает «от первого лица» → «из-за спины» → «спереди» с плавным переходом;
## камера сзади/спереди не проходит сквозь блоки.

signal camera_mode_changed(mode: CameraMode)

enum CameraMode { FIRST_PERSON, THIRD_BACK, THIRD_FRONT }

const THIRD_PERSON_DISTANCE := 4.0
## Сдвиг камеры вбок в виде из-за спины («за плечом»).
const SHOULDER_OFFSET := 0.55
const CAMERA_SMOOTH := 10.0
const DOUBLE_TAP_SEC := 0.3
const PITCH_LIMIT := deg_to_rad(89.0)
## Шаг ходьбы в блоках (для звука шагов).
const STEP_LENGTH := 2.0

var world: World
var body: VoxelBody
var motor: PlayerMotor
var interaction: BlockInteraction
## Инвентарь игрока (этап 4).
var inventory: PlayerInventory
var camera: Camera3D
var model: CharacterModel
## Внешность из редактора персонажа (CharacterModel.default_appearance()).
var appearance := {}
## false — игрок заморожен (загрузка мира, пауза).
var active := false
var yaw := 0.0
var pitch := 0.0
var camera_mode := CameraMode.FIRST_PERSON
## Чувствительность мыши по осям (знак — инверсия), из настроек.
var mouse_sens_x := 0.0025
var mouse_sens_y := 0.0025
var crouch_toggle := false
var sprint_toggle := false
var auto_jump := false
var camera_bob := true
var pad_look_speed := 1.0
## Учитывать вес инвентаря (перегруз замедляет) — опция в настройках.
var use_weight := false
## Принимать ввод без захвата мыши (тесты, headless).
var force_input := false
## Выживание (этап 5): множитель скорости от травм и болезней, можно ли бежать.
var survival_speed := 1.0
## Вязкость рыхлых слоёв (снег, этап 7): блок → доля потери скорости, когда стоишь в нём.
var _wade := PackedFloat32Array()
var can_sprint := true
## Прыжков с прошлого опроса SurvivalController (тратят выносливость).
var jumps := 0
var fov := 75.0

var _prev := PackedFloat64Array([0.0, 0.0, 0.0])
var _eye := PlayerMotor.STAND_EYE
var _cam_dist := 0.0
var _cam_turn := 0.0
var _hand: Node3D
var _hand_icon: Sprite3D
var _light: OmniLight3D
var _hand_swing := 0.0
var _last_jump_tap := -10.0
var _step_accum := 0.0
var _crouch_on := false
var _sprint_on := false
var _bob := 0.0


## Замедление в глубоком снегу 0…1 (блок у ног).
func wade() -> float:
	if motor.flying:
		return 0.0
	var b := world.get_block(floori(body.x), floori(body.y + 0.05), floori(body.z))
	return _wade[b] if b > 0 and b < _wade.size() else 0.0


func setup(p_world: World, x: float, y: float, z: float, p_yaw: float = 0.0, p_pitch: float = 0.0) -> void:
	world = p_world
	if inventory == null:
		inventory = PlayerInventory.new(world.registry)
	body = VoxelBody.new(world.is_solid)
	body.set_position(x, y, z)
	motor = PlayerMotor.new(body, world.is_fluid)
	yaw = p_yaw
	pitch = p_pitch
	_prev = PackedFloat64Array([x, y, z])
	world.bodies.append(body)
	var reg := world.registry
	_wade.resize(reg.block_count())
	for b in reg.block_count():
		var def := reg.block_by_num(b)
		if def != null and def.shape == &"layer" and not def.solid and def.material == &"snow":
			_wade[b] = 0.55 * def.layer_height


func _ready() -> void:
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.setup(world.registry, appearance)
	model.set_equipment(inventory.equipment)
	inventory.equipment_changed.connect(_on_equipment_changed)
	inventory.changed.connect(_on_inventory_changed)
	inventory.selected_changed.connect(func(_i: int) -> void: _on_inventory_changed())
	_light = OmniLight3D.new()
	_light.omni_range = 9.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = fov
	camera.near = 0.05
	camera.far = 2000.0
	camera.current = true
	add_child(camera)
	_hand = _make_hand()
	camera.add_child(_hand)
	_on_inventory_changed()
	interaction = BlockInteraction.new()
	interaction.name = "Interaction"
	interaction.player = self
	interaction.world = world
	add_child(interaction)
	_update_visual(0.0)


## Телепорт (мировые координаты); сбрасывает скорость и интерполяцию.
func teleport(x: float, y: float, z: float) -> void:
	body.set_position(x, y, z)
	motor.vx = 0.0
	motor.vy = 0.0
	motor.vz = 0.0
	_prev = PackedFloat64Array([x, y, z])
	world.update_origin(x, y, z)


func eye_world() -> PackedFloat64Array:
	return PackedFloat64Array([body.x, body.y + _eye, body.z])


## Направление взгляда головы (не камеры — в виде спереди камера смотрит на игрока).
func look_dir() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3.FORWARD


func input_allowed() -> bool:
	return force_input or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func swing() -> void:
	_hand_swing = 1.0
	model.swing()


func set_camera_mode(mode: CameraMode) -> void:
	camera_mode = mode
	camera_mode_changed.emit(mode)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.screen_relative
		yaw = wrapf(yaw - rel.x * mouse_sens_x, -PI, PI)
		pitch = clampf(pitch - rel.y * mouse_sens_y, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed(&"toggle_camera"):
		set_camera_mode(((camera_mode + 1) % 3) as CameraMode)


func _physics_process(delta: float) -> void:
	if not active or not world.is_loaded(floori(body.x), floori(body.z)):
		_prev = PackedFloat64Array([body.x, body.y, body.z])
		return
	_prev = PackedFloat64Array([body.x, body.y, body.z])
	var captured := input_allowed()
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if captured else Vector2.ZERO
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var wish := right * input.x - forward * input.y
	var jump := captured and Input.is_action_pressed(&"jump")
	if captured and Input.is_action_just_pressed(&"crouch"):
		_crouch_on = not _crouch_on
	if captured and Input.is_action_just_pressed(&"sprint"):
		_sprint_on = not _sprint_on
	if input.length() < 0.1:
		_sprint_on = false
	var sprint := captured and can_sprint and (_sprint_on if sprint_toggle else Input.is_action_pressed(&"sprint"))
	var crouch := captured and (_crouch_on if crouch_toggle else Input.is_action_pressed(&"crouch"))
	# Автопрыжок: идём в стену высотой в один блок, над ней свободно.
	if auto_jump and body.on_ground and body.hit_wall and wish.length() > 0.1 and not motor.flying:
		var fx := floori(body.x + wish.normalized().x * 0.6)
		var fz := floori(body.z + wish.normalized().y * 0.6)
		var fy := floori(body.y + 0.01)
		if world.is_solid(fx, fy, fz) and not world.is_solid(fx, fy + 1, fz) and not world.is_solid(fx, fy + 2, fz):
			jump = true
	motor.speed_mult = (inventory.overload_factor() if use_weight else 1.0) * survival_speed * (1.0 - wade())

	if captured and Input.is_action_just_pressed(&"jump") and world.game_mode == &"creative":
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_jump_tap < DOUBLE_TAP_SEC:
			motor.flying = not motor.flying
			_last_jump_tap = -10.0
		else:
			_last_jump_tap = now
	if world.game_mode != &"creative":
		motor.flying = false

	motor.step(delta, wish, jump, sprint, crouch)
	if motor.jumped:
		jumps += 1
	if motor.landed_fall > 0.0:
		EventBus.player_landed.emit(motor.landed_fall)
	_emit_steps()
	world.update_origin(body.x, body.y, body.z)


func _process(delta: float) -> void:
	# Обзор стиком геймпада.
	if input_allowed():
		var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		if look != Vector2.ZERO:
			yaw = wrapf(yaw - look.x * 2.6 * pad_look_speed * delta, -PI, PI)
			pitch = clampf(pitch - look.y * 2.0 * pad_look_speed * delta, -PITCH_LIMIT, PITCH_LIMIT)
	_update_visual(delta)


## Звук шагов: каждые STEP_LENGTH блоков по земле — группа звуков блока под ногами.
func _emit_steps() -> void:
	if not body.on_ground or motor.flying:
		_step_accum = 0.0
		return
	_step_accum += Vector2(body.moved_x, body.moved_z).length()
	if _step_accum < STEP_LENGTH * (0.6 if motor.crouching else 1.0):
		return
	_step_accum = 0.0
	var below := world.get_block(floori(body.x), floori(body.y - 0.05), floori(body.z))
	if below > 0:
		EventBus.player_step.emit(world.registry.block_by_num(below).sounds, world.to_scene(body.x, body.y, body.z))


func _update_visual(delta: float) -> void:
	var a := Engine.get_physics_interpolation_fraction() if active else 1.0
	position = world.to_scene(lerpf(_prev[0], body.x, a), lerpf(_prev[1], body.y, a), lerpf(_prev[2], body.z, a))
	var k := 1.0 - exp(-CAMERA_SMOOTH * delta) if delta > 0.0 else 1.0
	_eye = lerpf(_eye, motor.eye_height(), k)

	var target_dist := 0.0 if camera_mode == CameraMode.FIRST_PERSON else THIRD_PERSON_DISTANCE
	var target_turn := PI if camera_mode == CameraMode.THIRD_FRONT else 0.0
	_cam_dist = lerpf(_cam_dist, target_dist, k)
	_cam_turn = lerpf(_cam_turn, target_turn, k)

	# Базис камеры: взгляд головы, развёрнутый на _cam_turn вокруг вертикали (вид спереди).
	var view_pitch := pitch if _cam_turn < PI * 0.5 else -pitch
	var cam_basis := Basis.from_euler(Vector3(view_pitch, yaw + _cam_turn, 0.0))
	# Желаемый сдвиг камеры от головы: назад и (в виде из-за спины) вправо за плечо.
	var shoulder := SHOULDER_OFFSET * (_cam_dist / THIRD_PERSON_DISTANCE) * (1.0 - _cam_turn / PI)
	var offset := cam_basis * Vector3.BACK * _cam_dist + cam_basis.x * shoulder
	var dist := offset.length()
	if dist > 0.05:
		# Коллизия камеры: луч из головы к камере, камера останавливается перед блоком.
		var eye := eye_world()
		var hit := VoxelRaycast.cast(eye[0], eye[1], eye[2], offset / dist, dist + 0.3, world.is_solid)
		if hit["hit"]:
			offset *= clampf(float(hit["distance"]) - 0.3, 0.0, dist) / dist
	var bob := Vector3.ZERO
	if camera_bob and body.on_ground and not motor.flying:
		var spd := Vector2(motor.vx, motor.vz).length()
		_bob += delta * spd * 1.9
		var amp := clampf(spd / 6.0, 0.0, 1.0) * 0.035
		bob = cam_basis.x * sin(_bob) * amp + Vector3(0, absf(cos(_bob)) * amp, 0)
	camera.transform = Transform3D(cam_basis, Vector3(0.0, _eye, 0.0) + offset + bob)
	camera.fov = fov

	var third_person := _cam_dist > 0.6
	model.visible = third_person
	model.rotation.y = yaw
	model.animate(delta, Vector2(motor.vx, motor.vz).length(), pitch, motor.crouching)
	_hand.visible = not third_person
	_hand_swing = maxf(0.0, _hand_swing - delta * 5.0)
	var s := sin(_hand_swing * PI)
	_hand.rotation = Vector3(-0.35 - s * 0.9, 0.15, 0.1 - s * 0.3)


func _on_equipment_changed() -> void:
	model.set_equipment(inventory.equipment)
	_on_inventory_changed()


## Предмет в руке: иконка в руке (1-е и 3-е лицо), свет факела.
func _on_inventory_changed() -> void:
	if model == null or _hand_icon == null:
		return
	var held := inventory.held()
	model.set_held(held)
	_hand_icon.visible = held != null
	if held != null:
		_hand_icon.texture = ItemIcons.shared().icon(held.id)
	var light := inventory.hand_light()
	_light.light_energy = float(light[0]) / 15.0 * 1.6
	_light.light_color = light[1]
	_light.visible = light[0] > 0


func _make_hand() -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.36, -0.36, -0.72)
	_hand_icon = Sprite3D.new()
	_hand_icon.pixel_size = 0.32 / 64.0
	_hand_icon.position = Vector3(-0.02, 0.1, -0.3)
	_hand_icon.rotation_degrees = Vector3(0, 70, 0)
	_hand_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_hand_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_hand_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand_icon.visible = false
	pivot.add_child(_hand_icon)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(String(CharacterModel.default_appearance().merged(appearance, true)["skin"]))
	mat.roughness = 0.9
	mesh.material = mat
	mi.mesh = mesh
	mi.position = Vector3(0, 0, -0.15)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	return pivot
