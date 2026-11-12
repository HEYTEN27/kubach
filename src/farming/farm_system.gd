class_name FarmSystem
extends Node
## Ферма в игре (этап 9, раздел 8 ТЗ). Культуры — блоки стадий crop_<id>_<k> + сущность блока
## { type: crop, crop, p, t, bad, fert, wet_until }: рост досчитывается по игровому времени, в том
## числе за то время, пока колонна была выгружена (до MAX_CATCHUP_DAYS, при текущем сезоне).
## Условия: сезон, температура воздуха клетки (биом, сезон, высота, погода; в теплице +10 °C и
## сезон не важен; рядом печь или костёр — теплее), вода (грядка у воды в 4 блоках, дождь под
## открытым небом, лейка, разбрызгиватель у воды), удобрение, сорняки рядом, свет (крыша без
## стекла — темно). Сорняки появляются на соседних пустых грядках. Вне сезона и в холод
## однолетники через wither_days вянут, многолетники засыпают.
## Игрок: мотыга — вскопать, семена — посадить, удобрение и лейка — ПКМ, спелое — ПКМ собрать
## (однолетник пересаживается, многолетник откатывается на regrow_stage), сломать — урожай или семя.

const TICK_SEC := 1.0
## Сколько культур проверяется за тик (остальные — в следующих тиках по кругу).
const BUDGET := 160
const MAX_CATCHUP_DAYS := 30.0
const WATER_RADIUS := 4
const SPRINKLER_RADIUS := 4
const WEED_CHANCE_PER_DAY := 0.12
const WATERING_HOURS := 24.0
const REACH := 4.5

var world: World
var clock: GameClock
## Константы выживания (температура воздуха — EnvironmentProbe.air_temperature).
var cfg := {}
var weather: WeatherSystem
var stations: StationSystem
var player: Player
## Позиции культур в загруженных колоннах.
var crops := {}
var sprinklers := {}
var stat_ms := 0.0
var _queue: Array[Vector3i] = []
var _left := 0.0
var _rng := RandomNumberGenerator.new()
var _farmland := 0
var _farmland_wet := 0
var _weed := 0
var _withered := 0
var _sprinkler := 0
var _crop_defs := {}


func _init() -> void:
	name = "Farm"
	_rng.randomize()


func setup(p_world: World, p_clock: GameClock, p_cfg: Dictionary, p_weather: WeatherSystem = null,
		p_stations: StationSystem = null, p_player: Player = null) -> void:
	world = p_world
	clock = p_clock
	cfg = p_cfg
	weather = p_weather
	stations = p_stations
	player = p_player
	var reg := world.registry
	_farmland = reg.block_num(&"farmland")
	_farmland_wet = reg.block_num(&"farmland_wet")
	_weed = reg.block_num(&"weed")
	_withered = reg.block_num(&"withered_crop")
	_sprinkler = reg.block_num(&"sprinkler")
	for id: StringName in reg.crop_ids:
		_crop_defs[id] = reg.get_entry("crops", id)
	world.chunks.column_loaded.connect(_on_column_loaded)
	world.chunks.column_unloading.connect(_on_column_unloading)
	world.block_changed.connect(_on_block_changed)
	if world.is_inside_tree():
		EventBus.block_broken.connect(_on_block_broken)


func crop_def(id: StringName) -> Dictionary:
	return _crop_defs.get(id, {})


# --- Рост ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK_SEC
	var t0 := Time.get_ticks_usec()
	if _queue.is_empty():
		for p: Vector3i in crops:
			_queue.append(p)
	var n := mini(BUDGET, _queue.size())
	var now := clock.total_minutes()
	for i in n:
		var p: Vector3i = _queue.pop_back()
		if crops.has(p):
			update_crop(p, now)
	stat_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Досчитать культуру до момента now (абсолютные игровые минуты).
func update_crop(p: Vector3i, now: float) -> void:
	var e := world.get_entity(p)
	var b := world.get_block(p.x, p.y, p.z)
	var reg := world.registry
	if e.get("type", "") != "crop" or b <= 0 or reg.block_crop[b] == 0:
		crops.erase(p)
		return
	var c := crop_def(StringName(e["crop"]))
	if c.is_empty():
		return
	var hours := clampf((now - float(e.get("t", now))) / 60.0, 0.0, MAX_CATCHUP_DAYS * 24.0)
	e["t"] = now
	if hours <= 0.0:
		return
	var cond := conditions(p, e, hours > 6.0)
	var res := CropGrowth.advance(e, c, cond, hours)
	_update_farmland(p, cond.get("wet", false))
	if res == "wither":
		crops.erase(p)
		world.set_block(p.x, p.y, p.z, _withered)
		world.set_entity(p, {})
		return
	_spread_weeds(p, hours)
	_set_stage(p, e, c)


## Условия роста в клетке. daily — средняя за сутки температура (для долгого досчёта).
func conditions(p: Vector3i, e: Dictionary, daily: bool = false) -> Dictionary:
	var reg := world.registry
	var roof := _roof(p)
	var greenhouse := roof == 1
	var dark := roof == 2
	var bi := world.biome_at(p.x, p.z)
	var bs := world.generator.biomes
	var bt := bs.temperature_c[bi] if bi >= 0 and bi < bs.count else 12.0
	var hour := 9.0 if daily else clock.hour()
	var temp := EnvironmentProbe.air_temperature(cfg, bt, clock.season(), hour, float(p.y),
		float(world.generator.sea_level), 15, false)
	if weather != null:
		temp += float(weather.values.get("temp", 0.0))
	if greenhouse:
		temp += CropGrowth.GREENHOUSE_WARMTH
	if stations != null:
		for hs: Array in stations.heat_sources():
			var d := Vector3(float(hs[0]) - p.x, float(hs[1]) - p.y, float(hs[2]) - p.z).length()
			temp += EnvironmentProbe.heat_falloff(float(hs[3]), d, 6.0) * 0.5
	var now := clock.total_minutes()
	var wet := float(e.get("wet_until", 0.0)) > now
	var near_water := _water_near(p, 1)
	if not wet:
		wet = near_water or _water_near(p, WATER_RADIUS) or _sprinkled(p)
	if not wet and weather != null and roof == 0 and weather.wetness > 0.3:
		wet = true
	return { "season": clock.season(), "temp": temp, "wet": wet, "fert": float(e.get("fert", 0.0)),
		"weeds": _weeds_around(p), "greenhouse": greenhouse, "dark": dark, "near_water": near_water }


## Что над культурой: 0 — небо, 1 — стекло (теплица), 2 — крыша (темно).
func _roof(p: Vector3i) -> int:
	var reg := world.registry
	for dy in range(1, 13):
		var b := world.get_block(p.x, p.y + dy, p.z)
		if b <= 0:
			continue
		var def := reg.block_by_num(b)
		if def.has_tag("glass"):
			return 1
		if reg.block_opaque[b] == 1:
			return 2
	return 0


func _water_near(p: Vector3i, r: int) -> bool:
	var reg := world.registry
	for dy in [-1, 0]:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var b := world.get_block(p.x + dx, p.y + dy, p.z + dz)
				if b > 0 and reg.block_fluid[b] != 0 and reg.block_heat[b] <= 0.0:
					return true
	return false


func _sprinkled(p: Vector3i) -> bool:
	for s: Vector3i in sprinklers:
		if absi(s.x - p.x) <= SPRINKLER_RADIUS and absi(s.z - p.z) <= SPRINKLER_RADIUS and absi(s.y - p.y) <= 2 \
				and _sprinkler_active(s):
			return true
	return false


## Разбрызгиватель работает, если рядом (6 соседей) вода.
func _sprinkler_active(s: Vector3i) -> bool:
	var reg := world.registry
	for d: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i.DOWN, Vector3i.UP]:
		var b := world.get_block(s.x + d.x, s.y + d.y, s.z + d.z)
		if b > 0 and reg.block_fluid[b] != 0 and reg.block_heat[b] <= 0.0:
			return true
	return false


func _weeds_around(p: Vector3i) -> int:
	var n := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dz != 0) and world.get_block(p.x + dx, p.y, p.z + dz) == _weed:
				n += 1
	return n


func _spread_weeds(p: Vector3i, hours: float) -> void:
	if _weed <= 0 or _rng.randf() >= 1.0 - pow(1.0 - WEED_CHANCE_PER_DAY, hours / 24.0):
		return
	var dx := _rng.randi_range(-1, 1)
	var dz := _rng.randi_range(-1, 1)
	if dx == 0 and dz == 0:
		return
	var q := p + Vector3i(dx, 0, dz)
	var below := world.get_block(q.x, q.y - 1, q.z)
	if world.get_block(q.x, q.y, q.z) == 0 and (below == _farmland or below == _farmland_wet):
		world.set_block(q.x, q.y, q.z, _weed)


func _update_farmland(p: Vector3i, wet: bool) -> void:
	var below := world.get_block(p.x, p.y - 1, p.z)
	if wet and below == _farmland:
		world.set_block(p.x, p.y - 1, p.z, _farmland_wet)
	elif not wet and below == _farmland_wet:
		world.set_block(p.x, p.y - 1, p.z, _farmland)


## Блок стадии по прогрессу (сущность переживает смену блока).
func _set_stage(p: Vector3i, e: Dictionary, c: Dictionary) -> void:
	var reg := world.registry
	var idx := reg.crop_ids.find(StringName(c["id"]))
	var stages := reg.crop_stage_blocks[idx]
	var want := stages[CropGrowth.stage_of(float(e["p"]), stages.size())]
	if world.get_block(p.x, p.y, p.z) != want:
		world.set_block(p.x, p.y, p.z, want)
	world.set_entity(p, e)
	crops[p] = true


# --- Посадка, уход, сбор ---------------------------------------------------------------------

## Посадить культуру crop_id над грядкой в p (p — клетка над грядкой). true — посажено.
func plant(p: Vector3i, crop_id: StringName) -> bool:
	var c := crop_def(crop_id)
	if c.is_empty():
		return false
	var below := world.get_block(p.x, p.y - 1, p.z)
	if below != _farmland and below != _farmland_wet:
		return false
	var idx := world.registry.crop_ids.find(crop_id)
	if not world.execute(GameAction.place_block(p, world.registry.crop_stage_blocks[idx][0])):
		return false
	world.set_entity(p, { "type": "crop", "crop": String(crop_id), "p": 0.0, "t": clock.total_minutes(), "bad": 0.0 })
	crops[p] = true
	return true


## Вскопать грядку (мотыга): почва с тегом tillable и воздух сверху.
func till(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	var def := world.registry.block_by_num(b) if b > 0 else null
	if def == null or not def.has_tag("tillable") or world.get_block(p.x, p.y + 1, p.z) != 0:
		return false
	return world.set_block(p.x, p.y, p.z, _farmland)


## Удобрить культуру в p. true — удобрено (сильнее прежнего удобрения).
func fertilize(p: Vector3i, power: float) -> bool:
	var e := world.get_entity(p)
	if e.get("type", "") != "crop" or float(e.get("fert", 0.0)) >= power:
		return false
	update_crop(p, clock.total_minutes())
	e = world.get_entity(p)
	e["fert"] = power
	world.set_entity(p, e)
	return true


## Полить 3×3 вокруг p. Возвращает число политых культур.
func water(p: Vector3i) -> int:
	var n := 0
	var until := clock.total_minutes() + WATERING_HOURS * 60.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var q := p + Vector3i(dx, dy, dz)
				var e := world.get_entity(q)
				if e.get("type", "") == "crop":
					e["wet_until"] = until
					world.set_entity(q, e)
					_update_farmland(q, true)
					n += 1
				elif world.get_block(q.x, q.y, q.z) == _farmland:
					world.set_block(q.x, q.y, q.z, _farmland_wet)
	return n


## Собрать спелую культуру ПКМ. true — собрано.
func harvest(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	var reg := world.registry
	if b <= 0 or reg.block_crop[b] == 0:
		return false
	var c := crop_def(reg.crop_ids[reg.block_crop[b] - 1])
	var stages := int(c.get("stages", 5))
	if reg.block_crop_stage[b] != stages - 1:
		return false
	var perennial := bool(c.get("perennial", false))
	var drops := CropGrowth.harvest(c, stages - 1, _rng, _hybrid_partner(p, c), not perennial)
	_drop(p, drops)
	var e := world.get_entity(p)
	e["p"] = CropGrowth.progress_of(int(c.get("regrow_stage", 2)), stages) if perennial else 0.0
	e["t"] = clock.total_minutes()
	e["fert"] = 0.0
	_set_stage(p, e, c)
	Audio.play_at("blocks/grass_break", world.to_scene(p.x + 0.5, p.y + 0.5, p.z + 0.5))
	return true


func _hybrid_partner(p: Vector3i, c: Dictionary) -> StringName:
	var reg := world.registry
	var partners := []
	for h: Dictionary in c.get("hybrids", []):
		partners.append(StringName(h["with"]))
	if partners.is_empty():
		return &""
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var b := world.get_block(p.x + dx, p.y, p.z + dz)
			if b > 0 and reg.block_crop[b] != 0 and reg.block_crop_stage[b] >= 2:
				var id := reg.crop_ids[reg.block_crop[b] - 1]
				if partners.has(id):
					return id
	return &""


func _drop(p: Vector3i, drops: Array) -> void:
	var stacks: Array[ItemStack] = []
	for d: Array in drops:
		var def := world.registry.item(d[0])
		if def != null and int(d[1]) > 0:
			stacks.append(ItemStack.create(def, int(d[1])))
	if not stacks.is_empty():
		world.items_dropped.emit(p.x + 0.5, p.y + 0.4, p.z + 0.5, stacks)


func _on_block_broken(p: Vector3i, block: int, _at: Vector3) -> void:
	var reg := world.registry
	if block > 0 and reg.block_crop[block] != 0:
		crops.erase(p)
		var c := crop_def(reg.crop_ids[reg.block_crop[block] - 1])
		if world.game_mode != &"creative":
			_drop(p, CropGrowth.harvest(c, reg.block_crop_stage[block], _rng, _hybrid_partner(p, c)))
		return
	# Дикие семена из травы (по биому).
	var def := reg.block_by_num(block) if block > 0 else null
	if def != null and def.material == &"plant" and def.has_tag("grass") and world.game_mode != &"creative":
		var bi := world.biome_at(p.x, p.z)
		var bid := String(world.generator.biomes.ids[bi]) if bi >= 0 else ""
		for id: StringName in _crop_defs:
			var c: Dictionary = _crop_defs[id]
			if (c.get("wild_biomes", []) as Array).has(bid) and _rng.randf() < float(c.get("wild_chance", 0.0)):
				_drop(p, [[StringName("%s_seeds" % id), 1]])
				break


func _on_block_changed(p: Vector3i, old: int, new: int) -> void:
	# Грядку под культурой сломали — культура выпадает.
	if (old == _farmland or old == _farmland_wet) and new != _farmland and new != _farmland_wet:
		var up := p + Vector3i.UP
		var b := world.get_block(up.x, up.y, up.z)
		if b > 0 and world.registry.block_crop[b] != 0:
			world.execute(GameAction.break_block(up))
	if new == _sprinkler and _sprinkler > 0:
		sprinklers[p] = true
	elif old == _sprinkler:
		sprinklers.erase(p)


func _on_column_loaded(c: Vector2i) -> void:
	var col: ChunkColumn = world.chunks.columns.get(c)
	if col == null:
		return
	for key: int in col.block_entities.keys():
		var e: Dictionary = col.block_entities[key]
		if e.get("type", "") == "crop":
			var lp := ChunkColumn.entity_pos(key)
			var p := Vector3i(c.x * 16 + lp.x, lp.y, c.y * 16 + lp.z)
			crops[p] = true
			_queue.push_front(p)
	if _sprinkler > 0:
		for si in col.sections.size():
			var sec: ChunkSection = col.sections[si]
			if sec == null or sec.is_uniform() or not sec.blocks.has(_sprinkler):
				continue
			for i in sec.blocks.size():
				if sec.blocks[i] == _sprinkler:
					sprinklers[Vector3i(c.x * 16 + (i & 15), WorldConst.MIN_Y + si * 16 + (i >> 8), c.y * 16 + ((i >> 4) & 15))] = true


func _on_column_unloading(c: Vector2i) -> void:
	for p: Vector3i in crops.keys():
		if p.x >> 4 == c.x and p.z >> 4 == c.y:
			crops.erase(p)
	for p: Vector3i in sprinklers.keys():
		if p.x >> 4 == c.x and p.z >> 4 == c.y:
			sprinklers.erase(p)
