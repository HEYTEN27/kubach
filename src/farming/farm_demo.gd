class_name FarmDemo
extends RefCounted
## Сцены для визуальных смоук-тестов этапа 9 (scripts/screenshot.sh … --open=farm|kitchen|fell):
## ферма перед игроком (культуры разных стадий, полив, разбрызгиватель, теплица, сорняки,
## плодовые деревья, саженцы), ряд кухонных станций, падающее срубленное дерево.
## Загон с животными (--open=animals).
## Камера по умолчанию смотрит на −Z, поэтому всё строится в z < игрока.

const CROPS: Array[StringName] = [&"wheat", &"carrot", &"cabbage", &"tomato", &"corn", &"sunflower",
	&"pumpkin", &"potato", &"strawberry", &"beet", &"flax", &"onion"]


static func build(kind: String, world: World, farm: FarmSystem, orchard: OrchardSystem, player: Player,
		animals: AnimalSystem = null) -> void:
	var b := player.body
	var base := Vector3i(floori(b.x), floori(b.y) - 1, floori(b.z))
	match kind:
		"farm":
			_farm(world, farm, orchard, base)
			_lift(player, 5.0)
		"kitchen":
			_kitchen(world, base)
		"fell":
			_fell(world, orchard, base, Vector3(b.x, b.y, b.z))
		"animals":
			_animals(world, animals, base)
			_lift(player, 3.0)


## Ровная площадка: grnd на уровне y, воздух над ней до +h.
static func _flatten(world: World, x0: int, x1: int, z0: int, z1: int, y: int, grnd: int, h: int = 12) -> void:
	var ch := PackedInt32Array()
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			for dy in range(-3, 0):
				ch.append_array([x, y + dy, z, Registry.block_num(&"loam")])
			ch.append_array([x, y, z, grnd])
			for dy in range(1, h):
				ch.append_array([x, y + dy, z, 0])
	world.apply_changes(ch)


static func _crop(world: World, farm: FarmSystem, p: Vector3i, id: StringName, progress: float) -> void:
	var c := farm.crop_def(id)
	if c.is_empty():
		return
	world.set_block(p.x, p.y - 1, p.z, Registry.block_num(&"farmland_wet"))
	var e := { "type": "crop", "crop": String(id), "p": progress, "t": farm.clock.total_minutes(), "bad": 0.0,
		"wet_until": farm.clock.total_minutes() + 24.0 * 60.0 }
	farm._set_stage(p, e, c)


static func _farm(world: World, farm: FarmSystem, orchard: OrchardSystem, base: Vector3i) -> void:
	var y := base.y
	var grass := Registry.block_num(&"turf")
	_flatten(world, base.x - 16, base.x + 16, base.z - 30, base.z + 4, y, grass, 24)
	# Грядки: два поля по 6 рядов, стадия растёт к дальнему краю, между рядами — канавы с водой.
	var water := Registry.block_num(&"water")
	for i in CROPS.size():
		var x := base.x - 11 + (i % 6) * 2
		var z0 := base.z - 4 if i < 6 else base.z - 12
		var rows := 7 if i < 6 else 5
		for k in rows:
			_crop(world, farm, Vector3i(x, y + 1, z0 - k), CROPS[i], clampf(0.1 + k * 0.16, 0.0, 1.0))
		if i % 2 == 0:
			for k in rows:
				world.set_block(x + 1, y, z0 - k, water)
	var sp := Vector3i(base.x + 1, y, base.z - 6)
	world.set_block(sp.x, sp.y, sp.z, water)
	world.set_block(sp.x, sp.y + 1, sp.z, Registry.block_num(&"sprinkler"))
	# Сорняки и увядшее.
	world.set_block(base.x + 2, y, base.z - 4, Registry.block_num(&"farmland"))
	world.set_block(base.x + 2, y + 1, base.z - 4, Registry.block_num(&"weed"))
	world.set_block(base.x + 2, y, base.z - 8, Registry.block_num(&"farmland"))
	world.set_block(base.x + 2, y + 1, base.z - 8, Registry.block_num(&"withered_crop"))
	# Теплица: стеклянный короб 5×5 с томатами и перцем внутри.
	var glass := Registry.block_num(&"glass")
	var g0 := Vector3i(base.x + 4, y + 1, base.z - 8)
	for dz in 5:
		for dx in 5:
			for dy in 4:
				var edge := dx == 0 or dx == 4 or dz == 0 or dz == 4 or dy == 3
				if edge and not (dz == 4 and dx == 2 and dy < 2):
					world.set_block(g0.x + dx, g0.y + dy, g0.z - dz, glass)
	for dz in range(1, 4):
		for dx in range(1, 4):
			_crop(world, farm, Vector3i(g0.x + dx, g0.y, g0.z - dz), &"pepper" if dx == 2 else &"tomato", 0.95)
	# Сад: яблоня, вишня, груша; саженцы; компостер.
	var tb := world.generator.trees
	var trees: Array[StringName] = [&"apple", &"cherry", &"pear"]
	for i in trees.size():
		orchard.grow_tree(Vector3i(base.x - 8 + i * 7, y + 1, base.z - 22), tb.index[trees[i]])
	_ripen(orchard)
	for i in 4:
		world.set_block(base.x - 9 + i * 2, y + 1, base.z - 18, Registry.block_num(StringName("sapling_%s" % [&"apple", &"plum", &"oak", &"birch"][i])))
	world.execute(GameAction.place_block(Vector3i(base.x + 9, y + 1, base.z - 3), Registry.block_num(&"compost_bin"), 2))


## Сад «как будто давно растёт»: пересмотр листвы так, будто прошло 20 суток (плоды дозрели).
static func _ripen(orchard: OrchardSystem) -> void:
	var now := orchard.clock.total_minutes()
	for c: Vector2i in orchard._cols.keys():
		orchard._cols[c] = now - 20.0 * 1440.0
		orchard.rescan_column(c, now)


## Камера над площадкой: игрок в режиме скриншота не падает (Player неактивен).
static func _lift(player: Player, dy: float) -> void:
	player.teleport(player.body.x, player.body.y + dy, player.body.z)


static func _kitchen(world: World, base: Vector3i) -> void:
	var y := base.y
	_flatten(world, base.x - 14, base.x + 14, base.z - 12, base.z + 3, y, Registry.block_num(&"oak_planks"), 16)
	var ids: Array[StringName] = [&"spit", &"frying_pan", &"cauldron", &"bread_oven", &"smokehouse", &"drying_rack",
		&"salting_barrel", &"ferment_barrel", &"butter_churn", &"juice_press", &"quern", &"kitchen_table", &"beehive", &"ice_box"]
	for i in ids.size():
		var row := i / 7
		var x := base.x - 9 + (i % 7) * 3
		var z := base.z - 4 - row * 3
		world.execute(GameAction.place_block(Vector3i(x, y + 1, z), Registry.block_num(ids[i]), 2))


static func _fell(world: World, orchard: OrchardSystem, base: Vector3i, from: Vector3) -> void:
	var y := base.y
	_flatten(world, base.x - 14, base.x + 14, base.z - 24, base.z + 3, y, Registry.block_num(&"turf"), 24)
	var tb := world.generator.trees
	var p := Vector3i(base.x - 4, y + 1, base.z - 12)
	var t: int = tb.index[&"apple"]
	orchard.grow_tree(p, t)
	_ripen(orchard)
	var lg := world.get_block(p.x, p.y, p.z)
	world.set_block(p.x, p.y, p.z, 0)
	FallingTree.time_scale = 0.08
	orchard.fell(p, lg, Vector3(p.x - 6.0, from.y, p.z + 0.5))


static func _animals(world: World, animals: AnimalSystem, base: Vector3i) -> void:
	var y := base.y
	_flatten(world, base.x - 14, base.x + 14, base.z - 22, base.z + 3, y, Registry.block_num(&"turf"), 16)
	var fence := Registry.block_num(&"fence_oak")
	var x0 := base.x - 9
	var x1 := base.x + 9
	var z0 := base.z - 18
	var z1 := base.z - 4
	for x in range(x0, x1 + 1):
		for z in [z0, z1]:
			if not (z == z1 and x == base.x):
				world.execute(GameAction.place_block(Vector3i(x, y + 1, z), fence, 2))
	for z in range(z0 + 1, z1):
		for x in [x0, x1]:
			world.execute(GameAction.place_block(Vector3i(x, y + 1, z), fence, 1))
	world.execute(GameAction.place_block(Vector3i(base.x, y + 1, z1), Registry.block_num(&"fence_gate"), 2))
	world.execute(GameAction.place_block(Vector3i(base.x - 3, y + 1, z0 + 1), Registry.block_num(&"feeder"), 2))
	world.execute(GameAction.place_block(Vector3i(base.x - 2, y + 1, z0 + 1), Registry.block_num(&"feeder"), 2))
	world.execute(GameAction.place_block(Vector3i(base.x + 2, y + 1, z0 + 1), Registry.block_num(&"water_trough"), 2))
	world.execute(GameAction.place_block(Vector3i(base.x + 3, y + 1, z0 + 1), Registry.block_num(&"water_trough"), 2))
	for i in 3:
		world.execute(GameAction.place_block(Vector3i(x1 - 1, y + 1, z0 + 2 + i), Registry.block_num(&"nest_box"), 3))
	for p: Vector3i in [Vector3i(x0 + 1, y + 1, z0 + 1), Vector3i(x0 + 2, y + 1, z0 + 1), Vector3i(x0 + 1, y + 2, z0 + 1)]:
		world.set_block(p.x, p.y, p.z, Registry.block_num(&"hay_bale"))
	if animals == null:
		return
	var layout := [[&"cow", -6, -8, true], [&"cow", -4, -12, true], [&"cow", -5, -10, false],
		[&"sheep", 0, -9, true], [&"sheep", 2, -11, true], [&"sheep", 1, -7, false],
		[&"pig", 5, -13, true], [&"pig", 6, -15, false], [&"goat", -1, -14, true], [&"goat", 3, -15, true],
		[&"chicken", 6, -7, true], [&"chicken", 7, -8, true], [&"chicken", 5, -9, false]]
	for e: Array in layout:
		var a := animals.spawn(e[0], base.x + float(e[1]) + 0.5, float(y + 1), base.z + float(e[2]) + 0.5, e[3])
		if a != null:
			a.yaw = float(int(e[1]) * 7 + int(e[2]) * 3) * 0.37
			a.graze = 1.0 if int(e[1]) % 2 == 0 else 0.0
	# Одну овцу остригли — видно, что шерсть снимается.
	for a: Animal in animals.animals:
		if a.id == &"sheep" and AnimalLife.is_adult(a, animals.def_of(a), animals.clock.total_minutes()):
			a.next[AnimalLife.product_index(animals.def_of(a), "shear")] = animals.clock.total_minutes() + 600.0
			break
