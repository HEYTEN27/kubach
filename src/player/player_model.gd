class_name PlayerModel
extends Node3D
## Временная блочная модель игрока для вида от третьего лица: голова, тело, руки, ноги из
## коробок с анимацией ходьбы. На этапе 4 её заменит модель из редактора персонажа.

const SKIN := Color(0.86, 0.68, 0.55)
const SHIRT := Color(0.38, 0.45, 0.32)
const PANTS := Color(0.28, 0.25, 0.22)
const HAIR := Color(0.25, 0.17, 0.11)

var _head: Node3D
var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _phase := 0.0
var _swing := 0.0


func _ready() -> void:
	_leg_l = _limb(Vector3(-0.125, 0.75, 0), Vector3(0.24, 0.75, 0.24), PANTS)
	_leg_r = _limb(Vector3(0.125, 0.75, 0), Vector3(0.24, 0.75, 0.24), PANTS)
	_torso = _limb(Vector3(0, 0.75, 0), Vector3(0.5, 0.72, 0.26), SHIRT, true)
	_arm_l = _limb(Vector3(-0.36, 1.44, 0), Vector3(0.2, 0.7, 0.2), SHIRT)
	_arm_r = _limb(Vector3(0.36, 1.44, 0), Vector3(0.2, 0.7, 0.2), SHIRT)
	_head = Node3D.new()
	_head.position = Vector3(0, 1.47, 0)
	add_child(_head)
	_box(_head, Vector3(0, 0.22, 0), Vector3(0.44, 0.44, 0.44), SKIN)
	_box(_head, Vector3(0, 0.42, 0.02), Vector3(0.46, 0.08, 0.46), HAIR)
	# Глаза — чтобы было видно, куда смотрит.
	_box(_head, Vector3(-0.1, 0.25, -0.225), Vector3(0.08, 0.06, 0.02), Color(0.1, 0.1, 0.12))
	_box(_head, Vector3(0.1, 0.25, -0.225), Vector3(0.08, 0.06, 0.02), Color(0.1, 0.1, 0.12))


## speed — горизонтальная скорость, pitch — наклон головы (рад).
func animate(delta: float, speed: float, pitch: float, crouching: bool) -> void:
	_phase += delta * speed * 2.2
	var amp := clampf(speed / 4.3, 0.0, 1.4) * 0.7
	var s := sin(_phase) * amp
	_leg_l.rotation.x = s
	_leg_r.rotation.x = -s
	_arm_l.rotation.x = -s * 0.8
	_swing = maxf(0.0, _swing - delta * 4.0)
	_arm_r.rotation.x = s * 0.8 - sin(_swing * PI) * 1.4
	_head.rotation.x = clampf(-pitch, -1.2, 1.2)
	_torso.rotation.x = 0.35 if crouching else 0.0
	position.y = -0.25 if crouching else 0.0


func swing() -> void:
	_swing = 1.0


## Конечность с шарниром в точке pivot; коробка свисает вниз (или вверх для тела).
func _limb(pivot: Vector3, size: Vector3, color: Color, up: bool = false) -> Node3D:
	var joint := Node3D.new()
	joint.position = pivot
	add_child(joint)
	_box(joint, Vector3(0, size.y * 0.5 if up else -size.y * 0.5, 0), size, color)
	return joint


func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh.material = mat
	mi.mesh = mesh
	mi.position = center
	parent.add_child(mi)
