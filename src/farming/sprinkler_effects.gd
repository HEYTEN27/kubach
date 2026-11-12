class_name SprinklerEffects
extends Node3D
## Брызги работающих разбрызгивателей (этап 9): постоянный GPU-эмиттер над каждым, у которого
## рядом вода, — только в радиусе RADIUS от игрока и не больше MAX_EMITTERS (остальные молчат).
## Проверка раз в CHECK_SEC; узлы переиспользуются.

const RADIUS := 40.0
const MAX_EMITTERS := 24
const CHECK_SEC := 0.5

var farm: FarmSystem
var player: Player
var _nodes := {}   # Vector3i → GPUParticles3D
var _left := 0.0
var _process_mat: ParticleProcessMaterial
var _mesh: QuadMesh


func _init() -> void:
	name = "SprinklerFx"


func setup(p_farm: FarmSystem, p_player: Player) -> void:
	farm = p_farm
	player = p_player
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 2.4
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.angular_velocity_min = 0.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.3))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	_process_mat = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.82, 0.9, 1.0, 0.65)
	var tex := "res://assets/textures/generated/particles/splash.png"
	if ResourceLoader.exists(tex):
		mat.albedo_texture = load(tex)
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(0.12, 0.12)
	_mesh.material = mat


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or farm == null or player == null:
		return
	_left = CHECK_SEC
	var px := player.body.x
	var py := player.body.y
	var pz := player.body.z
	var want := {}
	for s: Vector3i in farm.sprinklers:
		if want.size() >= MAX_EMITTERS:
			break
		var d := Vector3(s.x + 0.5 - px, s.y + 0.5 - py, s.z + 0.5 - pz)
		if d.length_squared() > RADIUS * RADIUS or not farm.sprinkler_active(s):
			continue
		want[s] = true
	for s: Vector3i in _nodes.keys():
		if not want.has(s):
			(_nodes[s] as Node).queue_free()
			_nodes.erase(s)
	for s: Vector3i in want:
		if not _nodes.has(s):
			var p := GPUParticles3D.new()
			p.amount = 48
			p.lifetime = 0.8
			p.local_coords = false
			p.process_material = _process_mat
			p.draw_pass_1 = _mesh
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 6, 10))
			add_child(p)
			_nodes[s] = p
		var node: GPUParticles3D = _nodes[s]
		node.global_position = farm.world.to_scene(s.x + 0.5, s.y + 1.05, s.z + 0.5)
		node.emitting = true
