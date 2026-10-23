class_name WorldBorder
extends Node3D
## Видимая граница мира (раздел 2.1): полупрозрачная «стена тумана», которая проявляется,
## когда игрок подходит ближе FADE_DISTANCE. Физически край держит VoxelBody.

const FADE_DISTANCE := 64.0
const WALL_WIDTH := 160.0

var world: World
var player: Player
var _walls: Array[MeshInstance3D] = []
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(0.78, 0.84, 0.9, 0.0)
	for i in 4:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(WALL_WIDTH, float(WorldConst.HEIGHT))
		q.material = _material
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_walls.append(mi)


func _process(_delta: float) -> void:
	if player == null:
		return
	var b := player.body
	var lim := float(WorldConst.WORLD_HALF)
	# −X, +X, −Z, +Z: расстояние до стены и точка стены напротив игрока.
	var specs := [
		[b.x + lim, Vector3(-lim, 0, b.z), PI * 0.5],
		[lim - b.x, Vector3(lim, 0, b.z), PI * 0.5],
		[b.z + lim, Vector3(b.x, 0, -lim), 0.0],
		[lim - b.z, Vector3(b.x, 0, lim), 0.0],
	]
	var closest := INF
	for i in 4:
		var dist: float = specs[i][0]
		var wall := _walls[i]
		wall.visible = dist < FADE_DISTANCE
		closest = minf(closest, dist)
		if wall.visible:
			var p: Vector3 = specs[i][1]
			wall.position = world.to_scene(p.x, (WorldConst.MIN_Y + WorldConst.MAX_Y) * 0.5, p.z)
			wall.rotation = Vector3(0, specs[i][2], 0)
	_material.albedo_color.a = clampf(1.0 - closest / FADE_DISTANCE, 0.0, 1.0) * 0.75
