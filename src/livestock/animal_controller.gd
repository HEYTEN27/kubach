class_name AnimalController
extends Node
## Действия игрока с животными (этап 9): ЛКМ — удар (урон оружия или инструмента, кулак — 1);
## ПКМ кормом, который вид ест, — накормить (сытое взрослое «влюбляется» — пара рядом даст
## детёныша); ПКМ пустым ведром — подоить; ножницами — остричь; пустой рукой — узнать состояние.
## ПКМ по калитке — открыть/закрыть. Работает раньше FarmController и BlockInteraction и гасит
## их клик, если действие выполнено.

signal message(text: String)

const REACH := 4.0

var world: World
var player: Player
var animals: AnimalSystem
## Животное под прицелом (для подсказки) или null.
var hovered: Animal
var _rng := RandomNumberGenerator.new()
var _gate := 0
var _gate_open := 0


func _init() -> void:
	name = "AnimalControl"
	process_priority = -10
	_rng.randomize()


func setup(p_world: World, p_player: Player, p_animals: AnimalSystem) -> void:
	world = p_world
	player = p_player
	animals = p_animals
	_gate = world.registry.block_num(&"fence_gate")
	_gate_open = world.registry.block_num(&"fence_gate_open")


func _process(_delta: float) -> void:
	hovered = null
	if player == null or not player.active or not player.input_allowed() or player.vehicle != null:
		return
	var eye := player.eye_world()
	var origin := Vector3(eye[0], eye[1], eye[2])
	var t: Dictionary = player.interaction.target
	var limit := REACH
	if t.get("hit", false):
		limit = minf(limit, float(t.get("distance", REACH)))
	var out := []
	hovered = animals.pick(origin, player.look_dir(), limit, out)
	if hovered != null:
		if Input.is_action_just_pressed(&"attack"):
			_attack(hovered, origin)
			player.interaction.suppress(0.35)
			player.swing()
		elif Input.is_action_just_pressed(&"use"):
			var text := interact(hovered)
			if text != "":
				message.emit(text)
			player.interaction.suppress(0.3)
			player.swing()
		return
	if Input.is_action_just_pressed(&"use") and t.get("hit", false) and not Input.is_action_pressed(&"crouch"):
		var p: Vector3i = t["block"]
		if toggle_gate(p):
			player.interaction.suppress(0.3)


func _attack(a: Animal, origin: Vector3) -> void:
	var d := player.inventory.held_def()
	var dmg := 1.0
	if d != null and (d.is_tool() or d.damage > 1.0):
		var info := ToolAssembly.tool_of(player.inventory.held(), d)
		dmg = maxf(float(info.get("damage", d.damage)), 1.0)
		if world.game_mode != &"creative" and player.inventory.damage_held():
			player.interaction.tool_broken.emit(d.id)
	animals.hit(a, dmg, origin)


## ПКМ по животному предметом в руке. Возвращает сообщение для игрока.
func interact(a: Animal) -> String:
	var d := animals.def_of(a)
	var now := animals.clock.total_minutes()
	var s := player.inventory.held()
	var held := player.inventory.held_def()
	var name := animals.display_name(a)
	var creative := world.game_mode == &"creative"
	# Корм.
	if held != null and AnimalLife.accepts(d, held):
		var was_love := AnimalLife.in_love(a, now)
		if not AnimalLife.feed(a, d, now):
			return "%s не голодна" % name if name.ends_with("а") else "%s не голоден" % name
		if not creative:
			player.inventory.consume_held()
		a.graze = 1.0
		Audio.play_at("animals/%s_idle" % d.get("sounds", ""), world.to_scene(a.x, a.y + 0.6, a.z))
		return "%s: влюблена — ищет пару" % name if AnimalLife.in_love(a, now) and not was_love else "%s: сыта" % name
	# Дойка: пустая ёмкость для жидкости (ведро).
	var milk := AnimalLife.product_index(d, "milk")
	if milk >= 0 and held != null and not held.fluid_container.is_empty() and String(held.fluid_container.get("fluid", "")) == "":
		if not AnimalLife.can_take(a, d, milk, now):
			return "%s: молока пока нет (нужны корм и вода, раз в сутки)" % name
		_receive(AnimalLife.take(a, d, milk, now, _rng))
		Audio.play_at("animals/milking", world.to_scene(a.x, a.y + 0.6, a.z))
		return ""
	# Стрижка.
	var shear := AnimalLife.product_index(d, "shear")
	if shear >= 0 and held != null and held.is_tool() and String(ToolAssembly.tool_of(s, held).get("type", "")) == "shears":
		if not AnimalLife.can_take(a, d, shear, now):
			return "%s: шерсть ещё не отросла" % name
		var got := AnimalLife.take(a, d, shear, now, _rng)
		var item := world.registry.item(got[0])
		if item != null:
			world.items_dropped.emit(a.x, a.y + 0.8, a.z, [ItemStack.create(item, int(got[1]))])
		if not creative and player.inventory.damage_held():
			player.interaction.tool_broken.emit(held.id)
		Audio.play_at("animals/shearing", world.to_scene(a.x, a.y + 0.6, a.z))
		return ""
	return status_text(a)


## Состояние животного словами: возраст, сытость, вода, любовь, продукция.
func status_text(a: Animal) -> String:
	var d := animals.def_of(a)
	var now := animals.clock.total_minutes()
	var parts: PackedStringArray = [animals.display_name(a)]
	parts.append("сыто" if AnimalLife.is_fed(a, now) else "голодно")
	parts.append("вода рядом" if AnimalLife.is_watered(a, now) else "нет воды")
	if AnimalLife.in_love(a, now):
		parts.append("ищет пару")
	elif AnimalLife.is_adult(a, d, now) and now < a.breed_after:
		parts.append("отдыхает после родов %.0f ч" % ((a.breed_after - now) / 60.0))
	if not AnimalLife.is_adult(a, d, now):
		parts.append("вырастет через %.0f ч" % ((a.born + float(d.get("adult_days", 3.0)) * 1440.0 - now) / 60.0))
	return " · ".join(parts)


func _receive(got: Array) -> void:
	var item := world.registry.item(got[0])
	if item == null:
		return
	var left := player.inventory.add(ItemStack.create(item, int(got[1])))
	if left > 0:
		world.items_dropped.emit(player.body.x, player.body.y + 1.0, player.body.z, [ItemStack.create(item, left)])


## Открыть/закрыть калитку в p (поворот сохраняется). true — это была калитка.
func toggle_gate(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	if b <= 0 or (b != _gate and b != _gate_open) or _gate <= 0 or _gate_open <= 0:
		return false
	var e := world.get_entity(p)
	var facing := int(e.get("facing", 0))
	world.set_block(p.x, p.y, p.z, _gate_open if b == _gate else _gate)
	world.set_entity(p, { "type": "block", "facing": facing })
	world.chunks.notify_block_changed(p.x, p.y, p.z)
	Audio.play_at("blocks/gate_open" if b == _gate else "blocks/gate_close", world.to_scene(p.x + 0.5, p.y + 0.5, p.z + 0.5))
	return true
