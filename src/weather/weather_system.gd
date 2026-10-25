class_name WeatherSystem
extends Node
## Погода в игре (этап 7, разделы 3.1–3.3 ТЗ). Связывает чистую логику с миром:
## - WeatherSim по климату под игроком (ключи погоды биома, сезон, температура воздуха);
## - небо и свет (GraphicsRig): солнце и луна по окну дня сезона, фаза луны, облака по ветру,
##   мокрость поверхностей (лужи), вспышки молний; частицы (WeatherEffects);
## - поверхность (SurfaceTicker: снег слоями, лёд), огонь (FireSystem), молнии (LightningTarget,
##   громоотводы), дождь заливает костры (Station.rain);
## - выживание (SurvivalController.weather), звук (зацикленные фоны, гром с задержкой ~340 м/с);
## - смена сезона: цвета листвы и травы, LOD (сигнал season_changed для Game).

signal season_changed(index: int)

const VISUAL_INTERVAL := 0.2
const SURFACE_INTERVAL := 0.5
const FIRE_INTERVAL := 1.0
const CLIMATE_INTERVAL := 2.0
## Мокрость поверхностей: набирается в дождь, сохнет после (за игровой час).
const WET_PER_HOUR := 1.6
const DRY_PER_HOUR := 0.3
## Самый долгий шаг симуляции за раз (сон, долгая загрузка).
const MAX_STEP_HOURS := 24.0
## Звук идёт 340 м/с, 1 блок = 1 м.
const SOUND_SPEED := 340.0
const MIN_STRIKE_GAP := 1.2
const THUNDER_NEAR := 160.0

var world: World
var clock: GameClock
var player: Player
var rig: GraphicsRig
var effects: WeatherEffects
var survival: SurvivalController
var stations: StationSystem
var sim: WeatherSim
var surface: SurfaceTicker
var fire: FireSystem
## Громоотводы загруженных колонн (LightningTarget перехватывает удары рядом с ними).
var rods: Array[Vector3i] = []
## Значения погоды сейчас (WeatherSim.values).
var values := {}
var wetness := 0.0
## Температура воздуха под открытым небом у игрока (с погодой), °C.
var temperature := 10.0
var climate := {}
var running := false
var reduce_flashing := false
var moon_cycle_days := 8.0
var strikes := 0

var _last_minutes := -1.0
var _visual_left := 0.0
var _surface_left := 0.0
var _surface_hours := 0.0
var _fire_left := 0.0
var _fire_minutes := 0.0
var _climate_left := 0.0
var _strike_gap := 0.0
var _season := -1
var _rod_num := 0
var _fire_num := 0
var _leaf_nums := {}
var _leaf_density := 0.0
var _rng := RandomNumberGenerator.new()
var _last_type: StringName = &""


func _init() -> void:
	name = "Weather"
	_rng.randomize()


func setup(p_world: World, p_clock: GameClock, p_player: Player, p_rig: GraphicsRig, p_effects: WeatherEffects,
		p_survival: SurvivalController, p_stations: StationSystem, world_seed: int) -> void:
	world = p_world
	clock = p_clock
	player = p_player
	rig = p_rig
	effects = p_effects
	survival = p_survival
	stations = p_stations
	var reg := world.registry
	sim = WeatherSim.new(reg, world_seed)
	surface = SurfaceTicker.new(world)
	fire = FireSystem.new(world)
	_rod_num = maxi(0, reg.block_num(&"lightning_rod"))
	_fire_num = fire.fire_num
	for b in reg.block_count():
		var def := reg.block_by_num(b)
		if def != null and def.has_tag(&"leaves"):
			_leaf_nums[b] = true
	if reg.has_entry("sky", &"default"):
		var sky := reg.get_entry("sky", &"default")
		moon_cycle_days = float(sky.get("moon_cycle_days", 8.0))
		rig.moon_light = float(sky.get("moon_light", 0.2))
		rig.sky_shader.set_shader_parameter(&"star_brightness", float(sky.get("star_brightness", 1.0)))
	world.chunks.column_loaded.connect(_on_column_loaded)
	world.chunks.column_unloading.connect(_on_column_unloading)
	EventBus.block_placed.connect(_on_block_placed)
	_update_climate()
	values = sim.values(temperature)
	_update_sky(0.0)
	_apply_visuals()


## Включить погоду сразу (аргумент --weather, отладка).
func force(id: StringName) -> void:
	sim.force(id)
	values = sim.values(temperature)
	if id in [&"rain", &"downpour", &"thunderstorm", &"hail"]:
		wetness = 0.85
	_apply_visuals()


func _process(delta: float) -> void:
	var minutes := clock.total_minutes()
	var dmin := 0.0 if _last_minutes < 0.0 else maxf(0.0, minutes - _last_minutes)
	_last_minutes = minutes
	var hours := minf(dmin / 60.0, MAX_STEP_HOURS)
	_update_sky(delta)
	if running and hours > 0.0:
		sim.advance(hours, climate)
		var r := float(values.get("rain", 0.0))
		if r > 0.05:
			wetness = minf(1.0, wetness + r * WET_PER_HOUR * hours)
		else:
			wetness = maxf(0.0, wetness - DRY_PER_HOUR * hours * (0.5 + temperature / 30.0 if temperature > 0.0 else 0.3))
		_surface_hours += hours
		_fire_minutes += dmin
	values = sim.values(temperature)
	if sim.current != _last_type:
		_last_type = sim.current
		EventBus.weather_changed.emit(sim.current)
	_visual_left -= delta
	if _visual_left <= 0.0:
		_visual_left = VISUAL_INTERVAL
		_apply_visuals()
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		effects.update(delta, cam.global_position, values, rig.daylight, _leaf_density, clock.season() == &"autumn")
	if not running:
		return
	_climate_left -= delta
	if _climate_left <= 0.0:
		_climate_left = CLIMATE_INTERVAL
		_update_climate()
		_check_season()
	_surface_left -= delta
	if _surface_left <= 0.0 and _surface_hours > 0.0:
		_surface_left = SURFACE_INTERVAL
		var melt := float(sim.seasons.get(clock.season(), {}).get("snow_melt", 0.0)) * 0.2
		surface.tick(player.body.x, player.body.z, values, _temp_at, _surface_hours, melt)
		_surface_hours = 0.0
	_fire_left -= delta
	if _fire_left <= 0.0:
		_fire_left = FIRE_INTERVAL
		if _fire_minutes > 0.0:
			fire.tick(_fire_minutes, _rain_at)
			_douse_stations()
			_fire_minutes = 0.0
	_strike_gap -= delta
	var rate := float(values.get("lightning", 0.0))
	if rate > 0.0 and _strike_gap <= 0.0 and _rng.randf() < 1.0 - exp(-rate * hours):
		_strike_gap = MIN_STRIKE_GAP
		strike()


## Солнце, луна, звёзды и облака — каждый кадр (облака плывут).
func _update_sky(delta: float) -> void:
	var phase := SkyMath.moon_phase(clock.day, clock.minute, moon_cycle_days)
	rig.set_sky_time(clock.hour(), clock.day_window(), phase)
	rig.move_clouds(delta, player.body.x, player.body.z)


func _apply_visuals() -> void:
	rig.set_weather(values)
	rig.set_wetness(wetness, float(values.get("rain", 0.0)))
	survival.weather = values
	_update_sound()


## Климат под игроком: ключи погоды биома, сезон, температура под открытым небом.
func _update_climate() -> void:
	var b := player.body
	var bi := world.biome_at(floori(b.x), floori(b.z))
	var keys: Array = []
	var biome_temp := 12.0
	if bi >= 0 and bi < world.generator.biomes.count:
		biome_temp = world.generator.biomes.temperature_c[bi]
		var id: StringName = world.generator.biomes.ids[bi]
		if world.registry.has_entry("biomes", id):
			keys = world.registry.get_entry("biomes", id).get("weather", [])
	var base := EnvironmentProbe.air_temperature(survival.vitals.cfg, biome_temp, clock.season(), clock.hour(), b.y,
		float(world.generator.sea_level), 15, false)
	temperature = base + float(values.get("temp", 0.0))
	climate = { "weather": keys, "season": String(clock.season()), "temp": base }
	_leaf_density = _count_leaves()


## Температура воздуха в клетке под открытым небом (для снега и льда), °C.
func _temp_at(x: int, y: int, z: int) -> float:
	var bi := world.biome_at(x, z)
	var bt := world.generator.biomes.temperature_c[bi] if bi >= 0 and bi < world.generator.biomes.count else 12.0
	return EnvironmentProbe.air_temperature(survival.vitals.cfg, bt, clock.season(), clock.hour(), float(y),
		float(world.generator.sea_level), 15, false) + float(values.get("temp", 0.0))


## Идёт ли дождь над клеткой (огонь гаснет с шансом по силе дождя): только под открытым небом.
func _rain_at(p: Vector3i) -> bool:
	var r := float(values.get("rain", 0.0))
	if r < 0.05 or LightningTarget.top_y(world, p.x, p.z) > p.y:
		return false
	return _rng.randf() < r * 0.6


## Костёр под открытым небом заливает дождём.
func _douse_stations() -> void:
	var r := float(values.get("rain", 0.0))
	for p: Vector3i in stations.stations:
		var st: Station = stations.stations[p]
		st.rain = r if r > 0.05 and LightningTarget.top_y(world, p.x, p.z) <= p.y else 0.0


## Удар молнии рядом с игроком.
func strike() -> void:
	var b := player.body
	var p := LightningTarget.pick(world, floori(b.x), floori(b.z), _rng, 96, rods)
	if p.y < WorldConst.MIN_Y:
		return
	strikes += 1
	var block := world.get_block(p.x, p.y, p.z)
	var is_rod := block == _rod_num and _rod_num > 0
	var at := world.to_scene(p.x + 0.5, p.y + 1.0, p.z + 0.5)
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else at
	var dist := cam_pos.distance_to(at)
	effects.reduce_flashing = reduce_flashing
	effects.strike(at, cam_pos, clampf(1.4 - dist / 160.0, 0.3, 1.0))
	rig.flash((0.25 if reduce_flashing else 1.0) * clampf(1.3 - dist / 200.0, 0.35, 1.0))
	get_tree().create_timer(dist / SOUND_SPEED, false).timeout.connect(_thunder.bind(dist))
	if not is_rod:
		if block > 0 and world.registry.block_flammable[block] == 1 and _rng.randf() < 0.7:
			fire.ignite(p)
		var d := Vector3(b.x - (p.x + 0.5), b.y - (p.y + 1.0), b.z - (p.z + 0.5)).length()
		if d < 3.0 and survival.is_active():
			survival.vitals.damage(40.0 * (1.0 - d / 3.0) + 10.0, PlayerVitals.CAUSE_LIGHTNING)
	EventBus.lightning_struck.emit(p, is_rod)


func _thunder(dist: float) -> void:
	Audio.play_ambient("weather/thunder_near" if dist < THUNDER_NEAR else "weather/thunder_far",
		-clampf((dist - 40.0) / 30.0, 0.0, 14.0))


## Зацикленные фоны: дождь/снег/град (под крышей тише и глуше), ветер по силе.
func _update_sound() -> void:
	var t: Dictionary = sim.types.get(sim.current, {})
	var key := String(t.get("sound", ""))
	var outside := float(survival.env.get("outside", 1.0))
	var vol := lerpf(-12.0, 0.0, outside)
	if key != "" and outside < 0.5 and Audio.has_sound(key + "_roof"):
		key += "_roof"
		vol = -2.0
	Audio.set_loop(&"weather", key, vol)
	var wind := float(values.get("wind", 0.0))
	Audio.set_loop(&"wind", "weather/wind" if wind > 0.35 else "", lerpf(-24.0, -4.0, (wind - 0.35) / 0.65) + (outside - 1.0) * 10.0)


## Доля листвы над землёй вокруг игрока (для листопада): выборка верхних блоков.
func _count_leaves() -> float:
	var b := player.body
	var hits := 0
	for i in 24:
		var x := floori(b.x) + _rng.randi_range(-20, 20)
		var z := floori(b.z) + _rng.randi_range(-20, 20)
		var y := LightningTarget.top_y(world, x, z)
		if y >= WorldConst.MIN_Y and _leaf_nums.has(world.get_block(x, y, z)):
			hits += 1
	return clampf(hits / 10.0, 0.0, 1.0)


func _check_season() -> void:
	var s := GameClock.SEASONS.find(clock.season())
	if s != _season:
		var first := _season < 0
		_season = s
		if not first or s != world.chunks.season:
			season_changed.emit(s)


func _on_column_loaded(c: Vector2i) -> void:
	var col: ChunkColumn = world.chunks.columns.get(c)
	if col == null or (_rod_num <= 0 and _fire_num <= 0):
		return
	for si in col.sections.size():
		var sec: ChunkSection = col.sections[si]
		if sec == null or sec.is_uniform():
			continue
		var blocks := sec.blocks
		if not (_rod_num > 0 and blocks.has(_rod_num)) and not (_fire_num > 0 and blocks.has(_fire_num)):
			continue
		for i in blocks.size():
			var v := blocks[i]
			if v != _rod_num and v != _fire_num:
				continue
			var p := Vector3i(c.x * 16 + (i & 15), WorldConst.MIN_Y + si * 16 + (i >> 8), c.y * 16 + ((i >> 4) & 15))
			if v == _rod_num:
				rods.append(p)
			else:
				fire.register(p)


func _on_column_unloading(c: Vector2i) -> void:
	for i in range(rods.size() - 1, -1, -1):
		if rods[i].x >> 4 == c.x and rods[i].z >> 4 == c.y:
			rods.remove_at(i)
	for p: Vector3i in fire.fires.keys():
		if p.x >> 4 == c.x and p.z >> 4 == c.y:
			fire.fires.erase(p)


func _on_block_placed(p: Vector3i, block: int, _at: Vector3) -> void:
	if block == _rod_num and _rod_num > 0 and not rods.has(p):
		rods.append(p)


func to_dict() -> Dictionary:
	return { "sim": sim.to_dict(), "wetness": wetness }


func from_dict(d: Dictionary) -> void:
	if d.has("sim"):
		sim.from_dict(d["sim"])
	wetness = clampf(float(d.get("wetness", 0.0)), 0.0, 1.0)
	values = sim.values(temperature)
