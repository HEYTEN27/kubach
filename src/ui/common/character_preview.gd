class_name CharacterPreview
extends SubViewportContainer
## 3D-модель персонажа в окне (инвентарь, редактор): свой мир, камера, свет; вращается
## перетаскиванием мышью, в покое «дышит».

var model: CharacterModel
var yaw := 0.3
var auto_rotate := 0.0

var _viewport: SubViewport
var _pivot: Node3D
var _drag := false


func _init(size_px: Vector2i = Vector2i(260, 360)) -> void:
	stretch = true
	custom_minimum_size = Vector2(size_px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = size_px
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.2
	_viewport.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 150, 0)
	fill.light_energy = 0.35
	_viewport.add_child(fill)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	model = CharacterModel.new()
	_pivot.add_child(model)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, 4.0)
	cam.fov = 31.0
	cam.look_at_from_position(cam.position, Vector3(0, 1.0, 0))
	_viewport.add_child(cam)


func setup(registry: ContentRegistry, appearance: Dictionary, equip: Inventory = null) -> void:
	model.setup(registry, appearance)
	if equip != null:
		model.set_equipment(equip)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		yaw += event.relative.x * 0.012
		accept_event()


func _process(delta: float) -> void:
	yaw += auto_rotate * delta
	_pivot.rotation.y = PI + yaw
	model.animate(delta, 0.0, 0.0, false)
