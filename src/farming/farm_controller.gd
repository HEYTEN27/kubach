class_name FarmController
extends Node
## Действия игрока на ферме (этап 9): ПКМ мотыгой по почве — грядка; семенами по грядке —
## посадить; удобрением по культуре — удобрить; лейкой — полить 3×3 (уровень воды из лейки);
## пустой рукой или чем угодно по спелой культуре — собрать урожай. Работает раньше
## BlockInteraction и гасит её клик, если действие выполнено.

signal message(text: String)

var world: World
var player: Player
var farm: FarmSystem


func _init() -> void:
	name = "FarmControl"
	process_priority = -9


func setup(p_world: World, p_player: Player, p_farm: FarmSystem) -> void:
	world = p_world
	player = p_player
	farm = p_farm


func _process(_delta: float) -> void:
	if player == null or not player.active or not player.input_allowed() or player.vehicle != null:
		return
	if not Input.is_action_just_pressed(&"use") or Input.is_action_pressed(&"crouch"):
		return
	var t: Dictionary = player.interaction.target
	if not t.get("hit", false):
		return
	var p: Vector3i = t["block"]
	if use_on(p, t["normal"]):
		player.interaction.suppress(0.25)
		player.swing()


## Применить предмет в руке к блоку p (нормаль грани под прицелом). true — что-то сделано.
func use_on(p: Vector3i, normal: Vector3i) -> bool:
	var reg := world.registry
	var s := player.inventory.held()
	var d := player.inventory.held_def()
	var b := world.get_block(p.x, p.y, p.z)
	var is_crop := b > 0 and reg.block_crop[b] != 0
	# Лейка.
	if d != null and d.tags.has("watering_can"):
		if String(d.fluid_container.get("fluid", "")) == "":
			return false
		var n := farm.water(p if is_crop else p + Vector3i.UP)
		_use_water(s, d)
		Audio.play_at("fluids/bucket_pour", world.to_scene(p.x + 0.5, p.y + 1.0, p.z + 0.5))
		return n >= 0
	# Удобрение.
	if d != null and d.fertilizer > 0.0:
		var cp := p if is_crop else p + Vector3i.UP
		if farm.fertilize(cp, d.fertilizer):
			if world.game_mode != &"creative":
				player.inventory.consume_held()
			return true
		return false
	# Семена.
	if d != null and d.plant != &"" and normal == Vector3i.UP:
		if farm.plant(p + Vector3i.UP, d.plant):
			if world.game_mode != &"creative":
				player.inventory.consume_held()
			return true
		message.emit("Сажать можно только на вскопанную грядку")
		return false
	# Мотыга.
	if d != null and d.is_tool() and String(ToolAssembly.tool_of(s, d).get("type", d.tool.get("type", ""))) == "hoe":
		if farm.till(p):
			Audio.play_at("blocks/dirt_place", world.to_scene(p.x + 0.5, p.y + 1.0, p.z + 0.5))
			if world.game_mode != &"creative" and player.inventory.damage_held():
				player.interaction.tool_broken.emit(d.id)
			return true
		return false
	# Сбор спелого.
	if is_crop:
		return farm.harvest(p)
	return false


func _use_water(s: ItemStack, d: ItemDef) -> void:
	if world.game_mode == &"creative":
		return
	var left := int(s.data.get("amount", int(d.fluid_container.get("capacity", 8)))) - 1
	var inv := player.inventory
	if left <= 0:
		var empty := world.registry.item(StringName(d.fluid_container.get("empty", "")))
		inv.hotbar.set_stack(inv.selected, ItemStack.create(empty, 1) if empty != null else null)
	else:
		var rest := s.copy()
		rest.data["amount"] = left
		inv.hotbar.set_stack(inv.selected, rest)
