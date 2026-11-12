class_name SpoilageSystem
extends Node
## Порча еды в игре (этап 9): раз в TICK_SEC стареет еда у игрока (температура вокруг него),
## в хранилищах загруженных колонн (температура места: под землёй и под крышей прохладнее —
## погреб; ледник с тегом cooling — ещё медленнее), на станциях и на земле. Хранилища помнят
## время последнего пересчёта (spoil_t в данных блока), поэтому еда в выгруженных колоннах
## досчитывается при загрузке. Настройка «Порча еды» выключает систему.

const TICK_SEC := 5.0
const MAX_HOURS := 24.0 * 120.0

var world: World
var clock: GameClock
var player: Player
var survival: SurvivalController
var stations: StationSystem
var dropped: DroppedItems
var enabled := true
var _left := 0.0
var _last := -1.0
var _rng := RandomNumberGenerator.new()
var _sky_cache := {}   # Vector3i хранилища → открытость небу 0…15


func _init() -> void:
	name = "Spoilage"
	_rng.randomize()


func setup(p_world: World, p_clock: GameClock, p_player: Player, p_survival: SurvivalController,
		p_stations: StationSystem, p_dropped: DroppedItems) -> void:
	world = p_world
	clock = p_clock
	player = p_player
	survival = p_survival
	stations = p_stations
	dropped = p_dropped


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK_SEC
	var now := clock.total_minutes()
	if _last < 0.0:
		_last = now
		return
	var hours := clampf((now - _last) / 60.0, 0.0, MAX_HOURS)
	_last = now
	if not enabled or hours <= 0.0:
		return
	# Игрок: температура воздуха вокруг (в доме, у костра — по окружению).
	var ambient := float(survival.env.get("ambient", 15.0)) if survival != null else 15.0
	var pr := Spoilage.rate(ambient)
	for inv: Inventory in [player.inventory.hotbar, player.inventory.main, player.inventory.backpack]:
		age_inventory(inv, hours, pr)
	# Станции загруженных колонн.
	if stations != null:
		for p: Vector3i in stations.stations:
			var st: Station = stations.stations[p]
			var r := Spoilage.rate(_place_temp(p))
			for inv: Inventory in [st.inputs, st.outputs]:
				age_inventory(inv, hours, r)
	# Хранилища: каждое со своим временем (досчёт после выгрузки).
	for c: Vector2i in world.chunks.columns:
		var col: ChunkColumn = world.chunks.columns[c]
		for key: int in col.block_entities.keys():
			var e: Dictionary = col.block_entities[key]
			if not e.has("items"):
				continue
			var lp := ChunkColumn.entity_pos(key)
			var p := Vector3i(c.x * 16 + lp.x, lp.y, c.y * 16 + lp.z)
			age_container(p, e, now)
	# Предметы на земле — под открытым небом.
	if dropped != null:
		var r := Spoilage.rate(ambient)
		for s: ItemStack in dropped.stacks():
			Spoilage.age(s, world.registry.item(s.id), hours, r, _rng)


## Состарить содержимое хранилища в p до момента now.
func age_container(p: Vector3i, e: Dictionary, now: float) -> void:
	var t := float(e.get("spoil_t", now))
	var hours := clampf((now - t) / 60.0, 0.0, MAX_HOURS)
	e["spoil_t"] = now
	if hours <= 0.0:
		return
	var def := world.registry.block_by_num(world.get_block(p.x, p.y, p.z))
	var cooling := def != null and def.has_tag("cooling")
	var r := Spoilage.rate(_place_temp(p), cooling)
	var live: Inventory = world.live_container(p)
	if live != null:
		age_inventory(live, hours, r)
		return
	var items: Array = e["items"]
	for i in items.size():
		var d: Variant = items[i]
		if not d is Dictionary:
			continue
		var s := ItemStack.from_dict(d)
		if s != null and Spoilage.age(s, world.registry.item(s.id), hours, r, _rng):
			items[i] = s.to_dict()


func age_inventory(inv: Inventory, hours: float, r: float) -> void:
	if inv == null:
		return
	for i in inv.size():
		var s := inv.get_stack(i)
		if s != null and Spoilage.age(s, world.registry.item(s.id), hours, r, _rng):
			inv.set_stack(i, s)


## Температура хранения в клетке: воздух по биому и сезону (среднесуточная), под крышей и под
## землёй — ближе к подземным +10 °C (погреб).
func _place_temp(p: Vector3i) -> float:
	var sky: int = _sky_cache.get(p, -1)
	if sky < 0:
		sky = survival.probe.sky_exposure(p.x + 0.5, p.y + 1.0, p.z + 0.5) if survival != null else 15
		if _sky_cache.size() > 4096:
			_sky_cache.clear()
		_sky_cache[p] = sky
	var bi := world.biome_at(p.x, p.z)
	var bs := world.generator.biomes
	var bt := bs.temperature_c[bi] if bi >= 0 and bi < bs.count else 12.0
	var cfg: Dictionary = survival.vitals.cfg if survival != null else {}
	return EnvironmentProbe.air_temperature(cfg, bt, clock.season(), 9.0, float(p.y), float(world.generator.sea_level),
		sky, false)
