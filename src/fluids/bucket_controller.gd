class_name BucketController
extends Node
## Сосуды для воды (этап 8): ведро и бурдюк. ПКМ пустым сосудом по воде — набрать (источник
## не убывает, конечная вода убирается из мира), ПКМ полным ведром по блоку — вылить конечную
## воду (столько уровней, сколько в ведре). Пить из сосуда — удержание ПКМ, когда прицел не на
## блоке или с Shift (SurvivalController). Вид воды (пресная, грязная, морская, чистая) едет в
## данных стопки: water_kind; уровни — amount. Всё через слой действий (TAKE_FLUID, POUR_FLUID).

signal message(text: String)

const REACH := 4.5

var world: World
var player: Player
var survival: SurvivalController


func setup(p_world: World, p_player: Player, p_survival: SurvivalController) -> void:
	world = p_world
	player = p_player
	survival = p_survival


func _process(_delta: float) -> void:
	if player == null or not player.active or not player.input_allowed():
		return
	if not Input.is_action_just_pressed(&"use") or Input.is_action_pressed(&"crouch") or player.interaction.is_suppressed():
		return
	var s := player.inventory.held()
	var d := player.inventory.held_def()
	if s == null or d == null or int(d.fluid_container.get("capacity", 0)) <= 0:
		return
	if String(d.fluid_container.get("fluid", "")) == "":
		fill(s, d)
	elif bool(d.fluid_container.get("pour", true)):
		pour(s, d)


## Набрать воду, на которую смотрит игрок. true — набрали.
func fill(s: ItemStack, d: ItemDef) -> bool:
	var eye := player.eye_world()
	var reg := world.registry
	var hit := VoxelRaycast.cast(eye[0], eye[1], eye[2], player.look_dir(), REACH,
		func(x: int, y: int, z: int) -> bool:
			var b := world.get_block(x, y, z)
			return b > 0 and reg.block_render[b] != BlockDef.RENDER_INVISIBLE)
	if not hit["hit"]:
		return false
	var p: Vector3i = hit["block"]
	var b := world.get_block(p.x, p.y, p.z)
	var water := reg.fluid_ids.find(&"water") + 1
	if b <= 0 or reg.block_fluid[b] != water:
		return false
	var cap := int(d.fluid_container["capacity"])
	var a := GameAction.take_fluid(p)
	if not world.execute(a):
		return false
	var got := mini(a.taken, cap)
	if a.taken > cap:
		# Лишнее — обратно (конечная вода не пропадает).
		world.execute(GameAction.pour_fluid(p, water, a.taken - cap))
	var filled := reg.item(StringName(d.fluid_container.get("filled", "")))
	if filled == null:
		return false
	var full := ItemStack.create(filled, 1)
	full.data["amount"] = got
	full.data["water_kind"] = String(survival.water_kind_at(p.x, p.z)) if survival != null else "fresh"
	_replace_held(s, full)
	Audio.play_at("fluids/bucket_fill", world.to_scene(p.x + 0.5, p.y + 0.8, p.z + 0.5))
	player.swing()
	return true


## Вылить воду из ведра к блоку под прицелом. true — вылили.
func pour(s: ItemStack, d: ItemDef) -> bool:
	var t: Dictionary = player.interaction.target
	if not t.get("hit", false):
		return false
	var tb: Vector3i = t["block"]
	var tdef := world.registry.block_by_num(world.get_block(tb.x, tb.y, tb.z))
	if tdef != null and (tdef.container_slots > 0 or tdef.is_bed() or tdef.is_station()):
		return false
	var p: Vector3i = tb + (t["normal"] as Vector3i)
	var fluid := world.registry.fluid_ids.find(StringName(d.fluid_container["fluid"])) + 1
	var amount := int(s.data.get("amount", int(d.fluid_container["capacity"])))
	var a := GameAction.pour_fluid(p, fluid, amount)
	if not world.execute(a):
		return false
	var left := amount - a.taken
	if left <= 0:
		var empty := world.registry.item(StringName(d.fluid_container.get("empty", "")))
		_replace_held(s, ItemStack.create(empty, 1) if empty != null else null)
	else:
		var rest := s.copy()
		rest.data["amount"] = left
		_replace_held(s, rest)
	Audio.play_at("fluids/bucket_pour", world.to_scene(p.x + 0.5, p.y + 0.5, p.z + 0.5))
	player.swing()
	return true


## Заменить один предмет в руке на другой (если в руке стопка — лишний в инвентарь или на землю).
func _replace_held(s: ItemStack, new_stack: ItemStack) -> void:
	var inv := player.inventory
	if s.count > 1:
		inv.consume_held()
		if new_stack != null and inv.add(new_stack) > 0:
			world.items_dropped.emit(player.body.x, player.body.y + 1.0, player.body.z, [new_stack])
		return
	inv.hotbar.set_stack(inv.selected, new_stack)
