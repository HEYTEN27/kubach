class_name BlockInteraction
extends Node
## Наведение на блок (луч DDA из глаз), подсветка, ломание с удержанием и установка блоков.
## Изменения мира — только через World.execute(GameAction).
##
## До этапа 4 (инвентарь) ставятся блоки из отладочной палитры: все блоки реестра, кроме
## воздуха и материнской породы; выбор — 1…9 и колесо мыши.

signal selection_changed(block: int)

const REACH_SURVIVAL := 5.0
const REACH_CREATIVE := 7.0
const PLACE_COOLDOWN := 0.22
const CREATIVE_BREAK_COOLDOWN := 0.2

var player: Player
var world: World
var target := {}
## 0…1 — прогресс ломания текущего блока.
var break_progress := 0.0
var palette: Array[int] = []
var selected := 0

var _break_block := Vector3i(0, 1 << 30, 0)
var _cooldown := 0.0
var _highlight: MeshInstance3D


func _ready() -> void:
	for n in world.registry.block_count():
		var def := world.registry.block_by_num(n)
		if n != 0 and (def.is_breakable() or def.render == &"liquid"):
			palette.append(n)
	_highlight = MeshInstance3D.new()
	_highlight.mesh = _make_outline()
	_highlight.top_level = true
	_highlight.visible = false
	add_child(_highlight)


func selected_block() -> int:
	return palette[selected] if not palette.is_empty() else 0


func select(index: int) -> void:
	if palette.is_empty():
		return
	selected = posmod(index, palette.size())
	selection_changed.emit(selected_block())


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_handle_selection_input()
	if not player.active or not player.input_allowed():
		_highlight.visible = false
		break_progress = 0.0
		return
	var creative := world.game_mode == &"creative"
	var eye := player.eye_world()
	target = VoxelRaycast.cast(eye[0], eye[1], eye[2], player.look_dir(),
		REACH_CREATIVE if creative else REACH_SURVIVAL, world.is_targetable)
	_highlight.visible = target["hit"]
	if target["hit"]:
		var b: Vector3i = target["block"]
		_highlight.global_position = world.to_scene(b.x, b.y, b.z)

	if Input.is_action_pressed(&"attack") and target["hit"]:
		_process_break(delta, creative)
	else:
		break_progress = 0.0
		_break_block = Vector3i(0, 1 << 30, 0)

	if Input.is_action_pressed(&"use") and target["hit"] and _cooldown <= 0.0:
		var p: Vector3i = target["block"] + target["normal"]
		if world.execute(GameAction.place_block(p, selected_block())):
			player.swing()
		_cooldown = PLACE_COOLDOWN
	if Input.is_action_just_pressed(&"pick_block") and target["hit"]:
		var b: Vector3i = target["block"]
		var idx := palette.find(world.get_block(b.x, b.y, b.z))
		if idx >= 0:
			select(idx)


func _process_break(delta: float, creative: bool) -> void:
	var pos: Vector3i = target["block"]
	if pos != _break_block:
		_break_block = pos
		break_progress = 0.0
	var def := world.registry.block_by_num(world.get_block(pos.x, pos.y, pos.z))
	if def == null or not def.is_breakable():
		break_progress = 0.0
		return
	if creative:
		if _cooldown <= 0.0:
			world.execute(GameAction.break_block(pos))
			player.swing()
			_cooldown = CREATIVE_BREAK_COOLDOWN
		return
	# hardness — время ломания голыми руками (инструменты — этапы 6 и 11).
	var before := break_progress
	break_progress += delta / maxf(def.hardness, 0.05)
	if floori(before * 4.0) != floori(break_progress * 4.0):
		player.swing()
	if break_progress >= 1.0:
		world.execute(GameAction.break_block(pos))
		break_progress = 0.0
		_break_block = Vector3i(0, 1 << 30, 0)


func _handle_selection_input() -> void:
	for i in 9:
		if Input.is_action_just_pressed(StringName("hotbar_%d" % (i + 1))):
			select(i)
	if Input.is_action_just_pressed(&"hotbar_next"):
		select(selected + 1)
	if Input.is_action_just_pressed(&"hotbar_prev"):
		select(selected - 1)


## Каркас куба 1×1×1 (чуть больше блока, чтобы не мерцал).
func _make_outline() -> ImmediateMesh:
	var m := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var e := 0.004
	var lo := Vector3(-e, -e, -e)
	var hi := Vector3(1 + e, 1 + e, 1 + e)
	var c := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	m.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for pair in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		m.surface_add_vertex(c[pair[0]])
		m.surface_add_vertex(c[pair[1]])
	m.surface_end()
	return m
