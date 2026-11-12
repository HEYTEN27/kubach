class_name VehicleSystem
extends Node
## Лодки и плоты в мире (этап 8): ПКМ предметом-плавсредством по воде — спустить на воду,
## ПКМ по лодке — сесть, Shift — сойти на берег рядом, ЛКМ по лодке (hits ударов) — разбить и
## забрать предметом. Работает раньше BlockInteraction (process_priority) и гасит её клик,
## если лодка ближе блока под прицелом. Лодки сохраняются в world.json (vehicles).

const REACH := 4.5
const MAX_VEHICLES := 64

var world: World
var player: Player
## Течение для лодок (FluidSystem.current_at).
var current_at: Callable
var boats: Array[Boat] = []
var _textures := {}


func _init() -> void:
	name = "Vehicles"
	process_priority = -10
	process_physics_priority = -10


func setup(p_world: World, p_player: Player) -> void:
	world = p_world
	player = p_player


func spawn(item: StringName, x: float, y: float, z: float, yaw: float) -> Boat:
	if boats.size() >= MAX_VEHICLES:
		return null
	var d := world.registry.item(item)
	if d == null or d.vehicle.is_empty():
		return null
	var b := Boat.new()
	b.setup(world, item, x, y, z, yaw, _texture(StringName(d.vehicle.get("texture_block", "oak_planks"))))
	b.current_at = current_at
	add_child(b)
	boats.append(b)
	return b


func _physics_process(delta: float) -> void:
	for b in boats:
		if not world.is_loaded(floori(b.body.x), floori(b.body.z)):
			continue
		var fwd := 0.0
		var turn := 0.0
		if b.rider != null and b.rider.input_allowed():
			var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
			fwd = -input.y
			turn = input.x
		b.step(delta, fwd, turn)
		if b.rider != null:
			var s := b.seat()
			b.rider.ride_at(s[0], s[1], s[2])
			b.rider.yaw = wrapf(b.rider.yaw - turn * float(b.def.get("turn", 1.6)) * delta * 0.5, -PI, PI)


func _process(_delta: float) -> void:
	if player == null or not player.active or not player.input_allowed():
		return
	if player.vehicle != null:
		if Input.is_action_just_pressed(&"crouch"):
			dismount()
		return
	var held := player.inventory.held_def()
	var use := Input.is_action_just_pressed(&"use")
	var attack := Input.is_action_just_pressed(&"attack")
	if not use and not attack:
		return
	var eye := player.eye_world()
	var dir := player.look_dir()
	var hit := _boat_under_cursor(eye, dir)
	var block_d := _block_distance()
	if hit.size() == 2 and float(hit[1]) < block_d:
		var b: Boat = hit[0]
		player.interaction.suppress(0.3)
		if use:
			mount(b)
		elif attack:
			b.hits_left -= 1
			player.swing()
			Audio.play_at("blocks/wood_place", world.to_scene(b.body.x, b.body.y + 0.3, b.body.z))
			if b.hits_left <= 0:
				_break(b)
		return
	if use and held != null and not held.vehicle.is_empty():
		_launch(held)


## Сесть в лодку.
func mount(b: Boat) -> void:
	if b.rider != null:
		return
	b.rider = player
	player.vehicle = b
	var s := b.seat()
	player.ride_at(s[0], s[1], s[2])


## Сойти на берег: ближайшая клетка рядом с лодкой, где можно стоять.
func dismount() -> void:
	var b: Boat = player.vehicle
	player.vehicle = null
	if b == null:
		return
	b.rider = null
	var best := PackedFloat64Array([b.body.x, b.body.y + 1.0, b.body.z])
	for r: float in [1.6, 2.4]:
		var found := false
		for i in 8:
			var a := TAU * i / 8.0
			var x := b.body.x + cos(a) * r
			var z := b.body.z + sin(a) * r
			for dy in range(-1, 3):
				var y := floori(b.body.y) + dy
				if world.is_solid(floori(x), y - 1, floori(z)) and not world.is_solid(floori(x), y, floori(z)) \
						and not world.is_solid(floori(x), y + 1, floori(z)) and not world.is_fluid(floori(x), y, floori(z)):
					best = PackedFloat64Array([x, float(y), z])
					found = true
					break
			if found:
				break
		if found:
			break
	player.teleport(best[0], best[1], best[2])


func _launch(held: ItemDef) -> void:
	var eye := player.eye_world()
	var reg := world.registry
	var hit := VoxelRaycast.cast(eye[0], eye[1], eye[2], player.look_dir(), REACH,
		func(x: int, y: int, z: int) -> bool:
			var b := world.get_block(x, y, z)
			return b > 0 and reg.block_render[b] != BlockDef.RENDER_INVISIBLE)
	if not hit["hit"]:
		return
	var p: Vector3i = hit["block"]
	var b := world.get_block(p.x, p.y, p.z)
	if b <= 0 or reg.block_fluid[b] == 0 or reg.block_heat[b] > 0.0:
		return
	var s := world.liquid_surface(p.x + 0.5, p.y + 0.5, p.z + 0.5)
	if s == -INF:
		return
	if spawn(held.id, p.x + 0.5, s - Boat.DRAFT, p.z + 0.5, player.yaw) == null:
		return
	player.interaction.suppress(0.3)
	if world.game_mode != &"creative":
		player.inventory.consume_held()
	Audio.play_at("fluids/splash", world.to_scene(p.x + 0.5, s, p.z + 0.5))


func _break(b: Boat) -> void:
	if b.rider != null:
		dismount()
	boats.erase(b)
	var d := world.registry.item(b.item)
	if d != null and world.game_mode != &"creative":
		world.items_dropped.emit(b.body.x, b.body.y + 0.5, b.body.z, [ItemStack.create(d, 1)])
	b.queue_free()


func _boat_under_cursor(eye: PackedFloat64Array, dir: Vector3) -> Array:
	var best: Boat = null
	var best_d := INF
	for b in boats:
		var d := b.ray_hit(eye[0], eye[1], eye[2], dir, REACH)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = b
	return [best, best_d] if best != null else []


func _block_distance() -> float:
	var t: Dictionary = player.interaction.target
	if not t.get("hit", false):
		return INF
	var p: Vector3i = t["block"]
	var e := player.eye_world()
	return Vector3(p.x + 0.5 - e[0], p.y + 0.5 - e[1], p.z + 0.5 - e[2]).length() - 0.5


func _texture(block_id: StringName) -> Texture2D:
	if _textures.has(block_id):
		return _textures[block_id]
	var tex: Texture2D = null
	var bt := world.chunks.materials.textures if world.chunks.materials != null else null
	var bdef := world.registry.block(block_id)
	if bt != null and bt.albedo != null and bdef != null:
		var info := bt.set_info(String(bdef.texture_side))
		if not info.is_empty():
			var img := bt.albedo.get_layer_data(int(info["first"]))
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	_textures[block_id] = tex
	return tex


func to_array() -> Array:
	var out := []
	for b in boats:
		out.append(b.to_dict())
	return out


func from_array(arr: Array) -> void:
	for d: Dictionary in arr:
		spawn(StringName(d.get("item", "")), float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)),
			float(d.get("yaw", 0.0)))
