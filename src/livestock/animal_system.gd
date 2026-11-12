class_name AnimalSystem
extends Node3D
## Домашние животные в игре (этап 9, раздел 8 ТЗ: животноводство).
## - Дикие стада появляются в новых (не из сохранения) колоннах по биомам вида (data/animals.json).
## - Животные в загруженных колоннах в радиусе SIM_RADIUS от игрока ходят: бродят, идут за
##   игроком с кормом в руке, к кормушке, когда голодны, к партнёру, когда «влюблены»; убегают от
##   удара. Тело — VoxelBody (как у игрока); изгородь для них выше прыжка.
## - Жизнь (раз в LIFE_SEC): вода рядом (поилка или вода в WATER_RADIUS), куры несутся в гнездо
##   рядом или на землю, навоз и перья падают, детёныши растут.
## - Животные в выгруженных колоннах заморожены; всё хранится в world.json → animals.

signal message(text: String)

const SIM_RADIUS := 72.0
const RENDER_RADIUS := 80.0
const LOD_RADIUS := 28.0
## Голос: шанс за тик жизни на животное рядом с игроком.
const VOICE_CHANCE := 0.015
const VOICE_RADIUS := 24.0
const LIFE_SEC := 2.0
const WATER_RADIUS := 6
const FEEDER_RADIUS := 12.0
const NEST_RADIUS := 8.0
const FOLLOW_RADIUS := 9.0
const MATE_RADIUS := 10.0
const MAX_ANIMALS := 400
const GRAVITY := 25.0
const JUMP_SPEED := 7.6

var world: World
var clock: GameClock
var player: Player
var defs: Array[Dictionary] = []
var index := {}   # id → индекс вида
var animals: Array[Animal] = []
## Позиции кормушек, поилок и гнёзд в загруженных колоннах.
var feeders := {}
var troughs := {}
var nests := {}
var stat_ms := 0.0
var stat_sim := 0
var _views := {}   # uid → AnimalView
var _next_uid := 1
var _life_left := 0.0
var _rng := RandomNumberGenerator.new()
var _fence := PackedByteArray()
var _water := PackedByteArray()
var _feeder := 0
var _trough := 0
var _nest := 0


func _init() -> void:
	name = "Animals"
	_rng.randomize()


func setup(p_world: World, p_clock: GameClock, p_player: Player = null) -> void:
	world = p_world
	clock = p_clock
	player = p_player
	var reg := world.registry
	for e: Dictionary in reg.get_entries("animals"):
		index[StringName(e["id"])] = defs.size()
		defs.append(e)
	_fence.resize(reg.block_count())
	_water.resize(reg.block_count())
	for n in reg.block_count():
		var d := reg.block_by_num(n)
		_fence[n] = 1 if d != null and d.has_tag("fence") else 0
		_water[n] = 1 if reg.block_fluid[n] != 0 and reg.block_heat[n] <= 0.0 else 0
	_feeder = reg.block_num(&"feeder")
	_trough = reg.block_num(&"water_trough")
	_nest = reg.block_num(&"nest_box")
	world.chunks.column_loaded.connect(_on_column_loaded)
	world.chunks.column_unloading.connect(_on_column_unloading)
	world.block_changed.connect(_on_block_changed)


func def_of(a: Animal) -> Dictionary:
	return defs[a.kind]


func display_name(a: Animal) -> String:
	var d := def_of(a)
	var adult := AnimalLife.is_adult(a, d, clock.total_minutes())
	var n: Dictionary = d["name"] if adult else d["baby_name"]
	return String(n.get("ru", d["id"]))


## Новое животное вида id в точке (x, y, z) — y низ тела.
func spawn(id: StringName, x: float, y: float, z: float, adult: bool = true) -> Animal:
	if not index.has(id):
		return null
	var k: int = index[id]
	var d := defs[k]
	var now := clock.total_minutes()
	var a := Animal.new()
	a.uid = _next_uid
	_next_uid += 1
	a.kind = k
	a.id = id
	a.x = x
	a.y = y
	a.z = z
	a.yaw = _rng.randf() * TAU
	a.health = float(d.get("health", 10.0))
	a.born = now - (float(d.get("adult_days", 3.0)) * 1440.0 + 1.0 if adult else 0.0)
	AnimalLife.init_products(a, d, now)
	animals.append(a)
	return a


func remove(a: Animal) -> void:
	animals.erase(a)
	var v: AnimalView = _views.get(a.uid)
	if v != null:
		v.queue_free()
		_views.erase(a.uid)


func _loaded(a: Animal) -> bool:
	return world.is_loaded(floori(a.x), floori(a.z))


# --- Кадр ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var now := clock.total_minutes()
	var px := player.body.x if player != null else 0.0
	var pz := player.body.z if player != null else 0.0
	stat_sim = 0
	for a: Animal in animals.duplicate():
		if not _loaded(a):
			continue
		var dx := a.x - px
		var dz := a.z - pz
		if dx * dx + dz * dz > SIM_RADIUS * SIM_RADIUS:
			continue
		stat_sim += 1
		# Дальние (за LOD_RADIUS) — каждый третий кадр с тройным шагом.
		if dx * dx + dz * dz > LOD_RADIUS * LOD_RADIUS:
			a.lod_skip = (a.lod_skip + 1) % 3
			if a.lod_skip != 0:
				continue
			step(a, delta * 3.0, now)
		else:
			step(a, delta, now)
	stat_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _process(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		_life_left = LIFE_SEC
		life_tick(clock.total_minutes())
	_update_views(delta)


## Шаг одного животного: решение, движение, коллизии, прыжок, плавание.
func step(a: Animal, dt: float, now: float) -> void:
	var d := def_of(a)
	if a.body == null:
		a.body = VoxelBody.new(_animal_solid)
		var scale := 1.0 if AnimalLife.is_adult(a, d, now) else AnimalLife.BABY_SCALE
		a.body.half_width = float(d.get("width", 0.8)) * 0.5 * scale
		a.body.height = float(d.get("height", 1.2)) * scale
		a.body.set_position(a.x, a.y, a.z)
	a.timer -= dt
	if a.timer <= 0.0:
		think(a, now)
	var speed := float(d.get("speed", 1.2))
	var want := Vector2.ZERO
	match a.state:
		Animal.State.WANDER, Animal.State.FOLLOW, Animal.State.FEEDER, Animal.State.MATE:
			var to := Vector2(a.tx - a.x, a.tz - a.z)
			var stop := 1.8 if a.state == Animal.State.FOLLOW else 1.1
			if to.length() < stop:
				_arrive(a, now)
			else:
				want = to.normalized() * speed * (1.0 if a.state != Animal.State.FOLLOW else 1.3)
		Animal.State.FLEE:
			var away := Vector2(a.x - a.flee_from.x, a.z - a.flee_from.z)
			if away.length() < 0.01:
				away = Vector2.from_angle(a.yaw)
			want = away.normalized() * speed * 2.2
	# Плавная смена скорости и поворот по ходу.
	var k := clampf(dt * 6.0, 0.0, 1.0)
	a.vx = lerpf(a.vx, want.x, k)
	a.vz = lerpf(a.vz, want.y, k)
	var hs := Vector2(a.vx, a.vz).length()
	if hs > 0.05:
		a.yaw = lerp_angle(a.yaw, atan2(a.vx, a.vz), clampf(dt * 5.0, 0.0, 1.0))
	a.speed_now = hs
	a.walk_phase += hs * dt * 6.0
	a.graze = maxf(0.0, a.graze - dt * 0.5) if a.state != Animal.State.IDLE else a.graze
	# Вода: всплывать.
	var in_water := world.is_fluid(floori(a.x), floori(a.y + a.body.height * 0.4), floori(a.z))
	if in_water:
		a.vy = minf(a.vy + 14.0 * dt, 2.0)
	else:
		a.vy -= GRAVITY * dt
	var b := a.body
	# Стоит на земле без движения — коллизии не нужны (проверка опоры раз в ~0,5 с).
	if hs < 0.01 and absf(a.vy) < 0.01 and b.on_ground and not in_water:
		a.rest += dt
		if a.rest < 0.5:
			a.vy = 0.0
			return
		a.rest = 0.0
	else:
		a.rest = 0.0
	b.move(a.vx * dt, a.vy * dt, a.vz * dt)
	if b.on_ground and a.vy < 0.0:
		a.vy = 0.0
	# Уткнулось в ступеньку — прыжок (на изгородь не выйдет: она для них выше).
	if b.hit_wall and (b.on_ground or in_water) and hs > 0.2:
		var fx := floori(a.x + signf(a.vx) * (b.half_width + 0.3)) if absf(a.vx) > 0.1 else floori(a.x)
		var fz := floori(a.z + signf(a.vz) * (b.half_width + 0.3)) if absf(a.vz) > 0.1 else floori(a.z)
		var fy := floori(a.y)
		if not _animal_solid(fx, fy + 1, fz) and not _animal_solid(fx, fy + 2, fz):
			a.vy = JUMP_SPEED
		else:
			a.timer = minf(a.timer, 0.3)
	a.x = b.x
	a.y = b.y
	a.z = b.z
	if a.y < WorldConst.MIN_Y - 8:
		remove(a)


## Решение раз в несколько секунд.
func think(a: Animal, now: float) -> void:
	var d := def_of(a)
	a.timer = _rng.randf_range(2.0, 5.0)
	if a.state == Animal.State.FLEE and a.timer > 0.0 and a.health > 0.0 and _rng.randf() < 0.3:
		return
	# Игрок с кормом в руке.
	if player != null and player.inventory != null:
		var held := player.inventory.held_def()
		var dp := Vector2(player.body.x - a.x, player.body.z - a.z)
		if held != null and AnimalLife.accepts(d, held) and dp.length() < FOLLOW_RADIUS:
			a.state = Animal.State.FOLLOW
			a.tx = player.body.x
			a.tz = player.body.z
			a.timer = 0.5
			return
	# Влюблённое ищет пару.
	if AnimalLife.in_love(a, now):
		var mate := _find_mate(a, d, now)
		if mate != null:
			a.state = Animal.State.MATE
			a.tx = mate.x
			a.tz = mate.z
			a.timer = 0.6
			return
	# Голодное идёт к кормушке с подходящим кормом.
	if not AnimalLife.is_fed(a, now):
		var f := _feeder_with_food(a, d)
		if f != Vector3i(0, -9999, 0):
			a.state = Animal.State.FEEDER
			a.tx = f.x + 0.5
			a.tz = f.z + 0.5
			a.timer = 1.0
			return
	if _rng.randf() < 0.55:
		a.state = Animal.State.WANDER
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, 7.0)
		a.tx = a.x + cos(ang) * r
		a.tz = a.z + sin(ang) * r
	else:
		a.state = Animal.State.IDLE
		if _rng.randf() < 0.5:
			a.graze = 1.0


func _arrive(a: Animal, now: float) -> void:
	var d := def_of(a)
	match a.state:
		Animal.State.FEEDER:
			eat_from_feeder(a, Vector3i(floori(a.tx), 0, floori(a.tz)), now)
		Animal.State.MATE:
			var mate := _find_mate(a, d, now)
			if mate != null and Vector2(mate.x - a.x, mate.z - a.z).length() < 1.8 and AnimalLife.can_breed(a, mate, d, now):
				var baby := AnimalLife.breed(a, mate, d, now)
				baby.uid = _next_uid
				_next_uid += 1
				animals.append(baby)
				Audio.play_at("animals/%s_idle" % d.get("sounds", ""), world.to_scene(a.x, a.y + 0.5, a.z))
				message.emit("%s: родился детёныш" % String(d["name"].get("ru", d["id"])))
	a.state = Animal.State.IDLE
	a.timer = _rng.randf_range(1.0, 3.0)


func _find_mate(a: Animal, d: Dictionary, now: float) -> Animal:
	var best: Animal = null
	var bd := MATE_RADIUS
	for b: Animal in animals:
		if b == a or b.kind != a.kind or not AnimalLife.in_love(b, now) or not AnimalLife.is_adult(b, d, now):
			continue
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		if dist < bd:
			bd = dist
			best = b
	return best


func _feeder_with_food(a: Animal, d: Dictionary) -> Vector3i:
	var best := Vector3i(0, -9999, 0)
	var bd := FEEDER_RADIUS
	for f: Vector3i in feeders:
		var dist := Vector2(f.x + 0.5 - a.x, f.z + 0.5 - a.z).length()
		if dist >= bd or absf(f.y - a.y) > 3.0:
			continue
		var inv := world.get_container(f.x, f.y, f.z)
		if inv == null or _food_slot(inv, d) < 0:
			continue
		bd = dist
		best = f
	return best


func _food_slot(inv: Inventory, d: Dictionary) -> int:
	for i in inv.size():
		var s := inv.get_stack(i)
		if s != null and AnimalLife.accepts(d, world.registry.item(s.id)):
			return i
	return -1


## Поесть из кормушки рядом с колонкой (x, z). true — поело.
func eat_from_feeder(a: Animal, near: Vector3i, now: float) -> bool:
	var d := def_of(a)
	for f: Vector3i in feeders:
		if f.x != near.x or f.z != near.z:
			continue
		var inv := world.get_container(f.x, f.y, f.z)
		if inv == null:
			continue
		var i := _food_slot(inv, d)
		if i < 0:
			continue
		if not AnimalLife.feed(a, d, now):
			return false
		var s := inv.get_stack(i)
		s.count -= 1
		inv.set_stack(i, s if s.count > 0 else null)
		a.graze = 1.0
		return true
	return false


## Твёрдо ли для животного: блок твёрдый или над изгородью (её не перепрыгнуть).
func _animal_solid(x: int, y: int, z: int) -> bool:
	if world.is_solid(x, y, z):
		return true
	var below := world.get_block(x, y - 1, z)
	return below > 0 and _fence[below] == 1


# --- Жизнь -----------------------------------------------------------------------------------

## Вода, продукция, рост — для всех животных в загруженных колоннах.
func life_tick(now: float) -> void:
	for a: Animal in animals.duplicate():
		if not _loaded(a):
			continue
		var d := def_of(a)
		if not AnimalLife.is_watered(a, now) or now - a.water_seen > 60.0:
			if _water_near(a):
				a.water_seen = now
		# Выросший детёныш — тело пересоздаётся под взрослый размер.
		if a.body != null and AnimalLife.is_adult(a, d, now) and a.body.height < float(d.get("height", 1.2)) * 0.9:
			a.body = null
			var v: AnimalView = _views.get(a.uid)
			if v != null:
				v.queue_free()
				_views.erase(a.uid)
		if player != null and _rng.randf() < VOICE_CHANCE:
			var dv := Vector2(a.x - player.body.x, a.z - player.body.z)
			if dv.length() < VOICE_RADIUS:
				Audio.play_at("animals/%s_idle" % d.get("sounds", ""), world.to_scene(a.x, a.y + 0.8, a.z))
		for p: Array in AnimalLife.due(a, d, now, _rng):
			_give(a, p[0], int(p[1]), String(p[2]) == "lay")


func _water_near(a: Animal) -> bool:
	var cx := floori(a.x)
	var cy := floori(a.y)
	var cz := floori(a.z)
	for t: Vector3i in troughs:
		if absi(t.x - cx) <= WATER_RADIUS * 2 and absi(t.z - cz) <= WATER_RADIUS * 2 and absi(t.y - cy) <= 3:
			return true
	for dy in range(-2, 2):
		for dz in range(-WATER_RADIUS, WATER_RADIUS + 1):
			for dx in range(-WATER_RADIUS, WATER_RADIUS + 1):
				var b := world.get_block(cx + dx, cy + dy, cz + dz)
				if b > 0 and _water[b] == 1:
					return true
	return false


## Продукт: яйцо — в ближайшее гнездо (если есть место), иначе на землю рядом.
func _give(a: Animal, id: StringName, n: int, to_nest: bool) -> void:
	var item := world.registry.item(id)
	if item == null or n <= 0:
		return
	var s := ItemStack.create(item, n)
	if to_nest:
		for p: Vector3i in nests:
			if Vector3(p.x + 0.5 - a.x, p.y - a.y, p.z + 0.5 - a.z).length() > NEST_RADIUS:
				continue
			var inv := world.get_container(p.x, p.y, p.z)
			if inv != null:
				var left := inv.add(s)
				if left <= 0:
					return
				s.count = left
	world.items_dropped.emit(a.x, a.y + 0.3, a.z, [s])


# --- Взаимодействие --------------------------------------------------------------------------

## Удар по животному: урон, бегство, при смерти — добыча.
func hit(a: Animal, damage: float, from: Vector3) -> void:
	var d := def_of(a)
	a.health -= damage
	a.state = Animal.State.FLEE
	a.flee_from = from
	a.timer = 4.0
	a.vy = 4.0
	var v: AnimalView = _views.get(a.uid)
	if v != null:
		v.flash_hurt()
	var at := world.to_scene(a.x, a.y + 0.6, a.z)
	if a.health <= 0.0:
		Audio.play_at("animals/%s_death" % d.get("sounds", ""), at)
		if world.game_mode != &"creative":
			var stacks: Array[ItemStack] = []
			for dr: Array in AnimalLife.drops(d, AnimalLife.is_adult(a, d, clock.total_minutes()), _rng):
				var item := world.registry.item(dr[0])
				if item != null:
					stacks.append(ItemStack.create(item, int(dr[1])))
			if not stacks.is_empty():
				world.items_dropped.emit(a.x, a.y + 0.4, a.z, stacks)
		remove(a)
	else:
		Audio.play_at("animals/%s_hurt" % d.get("sounds", ""), at)


## Животное под лучом из глаза (мировые координаты) в пределах reach или null; t — в out[0].
func pick(origin: Vector3, dir: Vector3, reach: float, out: Array = []) -> Animal:
	var best: Animal = null
	var bt := reach
	var now := clock.total_minutes()
	for a: Animal in animals:
		var d := def_of(a)
		var sc := 1.0 if AnimalLife.is_adult(a, d, now) else AnimalLife.BABY_SCALE
		var hw := float(d.get("width", 0.8)) * 0.5 * sc + 0.1
		var h := float(d.get("height", 1.2)) * sc
		var box := AABB(Vector3(a.x - hw, a.y, a.z - hw), Vector3(hw * 2.0, h, hw * 2.0))
		if box.position.distance_to(origin) > reach + 4.0:
			continue
		var hitp: Variant = box.intersects_ray(origin, dir)
		if hitp == null:
			continue
		var t := (hitp as Vector3).distance_to(origin)
		if t < bt:
			bt = t
			best = a
	out.clear()
	out.append(bt)
	return best


# --- Вид -------------------------------------------------------------------------------------

func _update_views(delta: float) -> void:
	if player == null:
		return
	var now := clock.total_minutes()
	var px := player.body.x
	var pz := player.body.z
	var seen := {}
	for a: Animal in animals:
		var dx := a.x - px
		var dz := a.z - pz
		if dx * dx + dz * dz > RENDER_RADIUS * RENDER_RADIUS or not _loaded(a):
			continue
		seen[a.uid] = true
		var d := def_of(a)
		var v: AnimalView = _views.get(a.uid)
		if v == null:
			v = AnimalView.new()
			v.setup(d)
			add_child(v)
			_views[a.uid] = v
		var adult := AnimalLife.is_adult(a, d, now)
		var sc := 1.0 if adult else AnimalLife.BABY_SCALE
		v.position = world.to_scene(a.x, a.y, a.z)
		v.rotation = Vector3(0.0, a.yaw, 0.0)
		v.scale = Vector3(sc, sc, sc)
		var shear := AnimalLife.product_index(d, "shear")
		var sheared := shear >= 0 and adult and a.next.size() > shear and now < a.next[shear]
		v.animate(delta, a.walk_phase, a.speed_now / maxf(0.3, float(d.get("speed", 1.2))), a.graze, sheared)
	for uid: int in _views.keys():
		if not seen.has(uid):
			(_views[uid] as Node).queue_free()
			_views.erase(uid)


# --- Колонны и блоки -------------------------------------------------------------------------

func _on_block_changed(p: Vector3i, old: int, new: int) -> void:
	for pair: Array in [[_feeder, feeders], [_trough, troughs], [_nest, nests]]:
		var b: int = pair[0]
		if b <= 0:
			continue
		if new == b:
			(pair[1] as Dictionary)[p] = true
		elif old == b:
			(pair[1] as Dictionary).erase(p)


func _on_column_loaded(c: Vector2i) -> void:
	var col: ChunkColumn = world.chunks.columns.get(c)
	if col == null:
		return
	for si in col.sections.size():
		var sec: ChunkSection = col.sections[si]
		if sec == null or sec.is_uniform():
			continue
		for pair: Array in [[_feeder, feeders], [_trough, troughs], [_nest, nests]]:
			var b: int = pair[0]
			if b <= 0 or not sec.blocks.has(b):
				continue
			for i in sec.blocks.size():
				if sec.blocks[i] == b:
					(pair[1] as Dictionary)[Vector3i(c.x * 16 + (i & 15), WorldConst.MIN_Y + si * 16 + (i >> 8), c.y * 16 + ((i >> 4) & 15))] = true
	if not col.from_save:
		spawn_herds(c)


func _on_column_unloading(c: Vector2i) -> void:
	for dict: Dictionary in [feeders, troughs, nests]:
		for p: Vector3i in dict.keys():
			if p.x >> 4 == c.x and p.z >> 4 == c.y:
				dict.erase(p)
	for a: Animal in animals:
		if floori(a.x) >> 4 == c.x and floori(a.z) >> 4 == c.y:
			a.body = null


## Дикие стада в свежесгенерированной колонне: по хэшу колонны и биому в её середине.
func spawn_herds(c: Vector2i) -> int:
	if animals.size() >= MAX_ANIMALS:
		return 0
	var col: ChunkColumn = world.chunks.columns.get(c)
	var bi := world.biome_at(c.x * 16 + 8, c.y * 16 + 8)
	if col == null or bi < 0:
		return 0
	var bid := String(world.generator.biomes.ids[bi])
	var n := 0
	for k in defs.size():
		var d := defs[k]
		if not (d.get("biomes", []) as Array).has(bid):
			continue
		var h := GenRandom.hash3(world.world_seed, c.x, k, c.y, 133)
		if GenRandom.unit(h) >= float(d.get("spawn_chance", 0.05)):
			continue
		var rng := GenRandom.rng(h)
		var count := rng.randi_range(int(d.get("herd_min", 2)), maxi(int(d.get("herd_min", 2)), int(d.get("herd_max", 4))))
		var cx := c.x * 16 + rng.randi_range(4, 11)
		var cz := c.y * 16 + rng.randi_range(4, 11)
		for i in count:
			var x := clampi(cx + rng.randi_range(-3, 3), c.x * 16, c.x * 16 + 15)
			var z := clampi(cz + rng.randi_range(-3, 3), c.y * 16, c.y * 16 + 15)
			var y := _ground(x, z)
			if y == -9999:
				continue
			var a := spawn(StringName(d["id"]), x + 0.5, float(y), z + 0.5, rng.randf() > 0.2)
			if a != null:
				n += 1
	if n > 0:
		col.dirty = true
	return n


## Верх твёрдой земли в колонке (x, z) или −9999 (вода, листва, нет места).
func _ground(x: int, z: int) -> int:
	var reg := world.registry
	var y0 := world.generator.surface_height(x, z) + 1
	for y in range(y0 + 8, y0 - 8, -1):
		var below := world.get_block(x, y - 1, z)
		if below <= 0 or reg.block_solid[below] == 0:
			continue
		var here := world.get_block(x, y, z)
		if here < 0 or (here > 0 and (reg.block_solid[here] == 1 or _water[here] == 1)):
			return -9999
		if reg.block_render[below] == BlockDef.RENDER_CUTOUT or _animal_solid(x, y + 1, z):
			return -9999
		return y
	return -9999


# --- Сохранение ------------------------------------------------------------------------------

func to_array() -> Array:
	var out := []
	for a: Animal in animals:
		out.append(a.to_dict())
	return out


func from_array(arr: Array) -> void:
	for a: Animal in animals.duplicate():
		remove(a)
	animals.clear()
	for d: Variant in arr:
		if not d is Dictionary:
			continue
		var a := Animal.from_dict(d)
		if not index.has(a.id):
			continue
		a.kind = index[a.id]
		if a.uid <= 0:
			a.uid = _next_uid
		_next_uid = maxi(_next_uid, a.uid + 1)
		animals.append(a)
