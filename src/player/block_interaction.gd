class_name BlockInteraction
extends Node
## Наведение на блок (луч DDA из глаз), подсветка, ломание с удержанием и установка блоков.
## Изменения мира — только через World.execute(GameAction).
##
## Этап 4: ставится предмет из выбранной ячейки хотбара (в выживании расходуется), инструмент
## в руке ускоряет добычу подходящих блоков и изнашивается. ПКМ по сундуку открывает его
## (с Shift — ставит блок рядом). Средняя кнопка: в творческом — взять блок в руку.

## ПКМ по контейнеру: открыть окно хранилища.
signal container_requested(pos: Vector3i)
## Инструмент сломался.
signal tool_broken(item: StringName)

const REACH_SURVIVAL := 5.0
const REACH_CREATIVE := 7.0
const PLACE_COOLDOWN := 0.22
const CREATIVE_BREAK_COOLDOWN := 0.2

var player: Player
var world: World
var target := {}
## 0…1 — прогресс ломания текущего блока.
var break_progress := 0.0

var _break_block := Vector3i(0, 1 << 30, 0)
var _cooldown := 0.0
var _highlight: MeshInstance3D


func _ready() -> void:
	_highlight = MeshInstance3D.new()
	_highlight.mesh = _make_outline()
	_highlight.top_level = true
	_highlight.visible = false
	add_child(_highlight)


## Блок, который поставит предмет в руке (0 — предмет не ставится).
func selected_block() -> int:
	var d := player.inventory.held_def()
	return d.place_block if d != null else 0


func select(index: int) -> void:
	player.inventory.select(index)


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
		var b: Vector3i = target["block"]
		var def := world.registry.block_by_num(world.get_block(b.x, b.y, b.z))
		if def != null and def.container_slots > 0 and not Input.is_action_pressed(&"crouch"):
			if Input.is_action_just_pressed(&"use"):
				container_requested.emit(b)
			_cooldown = PLACE_COOLDOWN
		else:
			var block := selected_block()
			if block > 0 and world.execute(GameAction.place_block(b + target["normal"], block)):
				player.swing()
				if not creative:
					player.inventory.consume_held()
			_cooldown = PLACE_COOLDOWN
	if Input.is_action_just_pressed(&"pick_block") and target["hit"]:
		_pick_block(target["block"], creative)


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
	# hardness — время ломания голыми руками; подходящий инструмент делит его на speed.
	var before := break_progress
	break_progress += delta * break_speed(def, player.inventory.held_def()) / maxf(def.hardness, 0.05)
	if floori(before * 4.0) != floori(break_progress * 4.0):
		player.swing()
	if break_progress >= 1.0:
		var tool := player.inventory.held_def()
		if world.execute(GameAction.break_block(pos)) and tool != null and tool.is_tool() and def.hardness > 0.0:
			if player.inventory.damage_held():
				tool_broken.emit(tool.id)
		break_progress = 0.0
		_break_block = Vector3i(0, 1 << 30, 0)


## Во сколько раз быстрее голых рук: инструмент нужного типа и уровня не ниже требуемого —
## его speed; нужного типа, но слабее — половина; ножницы режут листву и растения.
static func break_speed(block: BlockDef, tool: ItemDef) -> float:
	if tool == null or not tool.is_tool():
		return 1.0
	var t: StringName = tool.tool.get("type", &"")
	var speed: float = tool.tool.get("speed", 1.0)
	if t == &"shears" and (block.material == &"leaves" or block.material == &"plant"):
		return speed
	if t == &"knife" and block.material == &"plant":
		return speed
	if t != block.tool:
		return 1.0
	if int(tool.tool.get("tier", 0)) < block.tool_tier:
		return maxf(1.0, speed * 0.5)
	return speed


func _pick_block(b: Vector3i, creative: bool) -> void:
	var def := world.registry.block_by_num(world.get_block(b.x, b.y, b.z))
	if def == null or world.registry.item(def.id) == null:
		return
	var inv := player.inventory
	for i in PlayerInventory.HOTBAR:
		var s := inv.hotbar.get_stack(i)
		if s != null and s.id == def.id:
			inv.select(i)
			return
	if creative:
		inv.hotbar.set_stack(inv.selected, ItemStack.create(world.registry.item(def.id), 64))


func _handle_selection_input() -> void:
	for i in 9:
		if Input.is_action_just_pressed(StringName("hotbar_%d" % (i + 1))):
			select(i)
	if Input.is_action_just_pressed(&"hotbar_next"):
		select(player.inventory.selected + 1)
	if Input.is_action_just_pressed(&"hotbar_prev"):
		select(player.inventory.selected - 1)


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
