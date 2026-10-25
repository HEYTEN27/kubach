class_name EnvironmentProbe
extends RefCounted
## Окружение игрока для PlayerVitals (раздел 3.2: «температура мира = биом + сезон + время
## суток + высота + погода»): температура воздуха, тепло от костров и лавы рядом, урон от
## контакта с блоком, вода у ног и у глаз. Чистые функции расчёта — статические (тестируются
## без мира), sample() собирает их по миру. Погода добавится на этапе 7 (ключ rain).

## Длина луча проверки укрытия, блоков.
const SHELTER_RAY := 40

var cfg := {}
var world: World
## Есть ли в секции источники тепла: instance_id секции → [version, bool]. Секция сканируется
## один раз после изменения — опрос стоит доли миллисекунды (в мире почти нет тёплых блоков).
var _heat_cache := {}
## Тепло горящих станций (этап 6): Callable() -> [[x, y, z, тепло], ...] (StationSystem).
var heat_sources: Callable


func _init(p_world: World, p_cfg: Dictionary) -> void:
	world = p_world
	cfg = p_cfg


## Температура воздуха, °C.
## sky — уровень небесного света 0..15 (0 — глубоко под землёй или в закрытом доме).
static func air_temperature(c: Dictionary, biome_temp: float, season: StringName, hour: float,
		y: float, sea_level: float, sky: int, in_water: bool) -> float:
	var t := biome_temp + float((c.get("season_temp", {}) as Dictionary).get(String(season), 0.0))
	# Суточный ход: теплее всего в 15:00, холоднее всего в 3:00.
	t += float(c.get("night_cold", 5.0)) * 0.5 * (cos((hour - 15.0) / 24.0 * TAU) - 1.0)
	# Высота: холоднее на altitude_lapse за каждые 10 блоков выше sea_level + 16.
	t -= maxf(0.0, y - sea_level - 16.0) * float(c.get("altitude_lapse", 0.6)) / 10.0
	# Укрытие и подземье: без неба температура стремится к постоянной подземной.
	var shelter := clampf((15.0 - float(sky)) / 15.0, 0.0, 1.0)
	t = lerpf(t, float(c.get("underground_temp", 10.0)), shelter * shelter)
	if in_water:
		t -= float(c.get("water_cold", 8.0))
	return t


## Тепло источника heat на расстоянии d блоков: быстро спадает, на heat_radius — почти ноль.
static func heat_falloff(heat: float, d: float, radius: float) -> float:
	if d > radius:
		return 0.0
	return heat * pow(1.0 - d / (radius + 1.0), 1.5)


## Сумма тепла блоков вокруг точки (px, py, pz). get_block(x, y, z) -> int (−1 — не загружено).
static func heat_around(heat_table: PackedFloat32Array, get_block: Callable,
		px: float, py: float, pz: float, radius: float) -> float:
	var r := int(ceil(radius))
	var cx := floori(px)
	var cy := floori(py)
	var cz := floori(pz)
	var total := 0.0
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var b: int = get_block.call(cx + dx, cy + dy, cz + dz)
				if b <= 0 or b >= heat_table.size():
					continue
				var h := heat_table[b]
				if h <= 0.0:
					continue
				var d := Vector3(cx + dx + 0.5 - px, cy + dy + 0.5 - py, cz + dz + 0.5 - pz).length()
				total += heat_falloff(h, d, radius)
	return minf(total, 45.0)


## Окружение в точке ног игрока (x, y, z — мировые double), eye_y — высота глаз.
## Возвращает словарь для PlayerVitals.tick (без ключей движения — их добавляет контроллер).
func sample(x: float, y: float, z: float, eye_y: float, clock: GameClock) -> Dictionary:
	var reg := world.registry
	var bx := floori(x)
	var bz := floori(z)
	var bi := world.biome_at(bx, bz)
	var biome_temp := 12.0
	var biome_id := &""
	if bi >= 0 and bi < world.generator.biomes.count:
		biome_temp = world.generator.biomes.temperature_c[bi]
		biome_id = world.generator.biomes.ids[bi]
	var sky := sky_exposure(x, y + 1.6, z)
	var feet_b := world.get_block(bx, floori(y + 0.2), bz)
	var head_b := world.get_block(bx, floori(eye_y), bz)
	var in_water := feet_b > 0 and reg.block_render[feet_b] == BlockDef.RENDER_LIQUID and reg.block_heat[feet_b] <= 0.0
	var head_in_water := head_b > 0 and reg.block_render[head_b] == BlockDef.RENDER_LIQUID and reg.block_heat[head_b] <= 0.0
	var ambient := air_temperature(cfg, biome_temp, clock.season(), clock.hour(), y,
		float(world.generator.sea_level), sky, in_water)
	var radius := float(cfg.get("heat_radius", 7.0))
	var heat := _heat_scan(x, y + 0.9, z, radius)
	if heat_sources.is_valid():
		for hs: Array in heat_sources.call():
			var d := Vector3(float(hs[0]) + 0.5 - x, float(hs[1]) + 0.5 - (y + 0.9), float(hs[2]) + 0.5 - z).length()
			heat = minf(45.0, heat + heat_falloff(float(hs[3]), d, radius))
	# Контакт: клетки, которые занимает тело (ноги и туловище).
	var contact := 0.0
	var cause := ""
	for b: int in [feet_b, world.get_block(bx, floori(y + 1.0), bz), world.get_block(bx, floori(y - 0.05), bz)]:
		if b > 0 and reg.block_contact[b] > contact:
			# Блок под ногами обжигает только если по нему идут (кактус — нет, лава/угли — да).
			contact = reg.block_contact[b]
			cause = "fire" if reg.block_heat[b] > 0.0 else "contact"
	return {
		"ambient": ambient, "heat": heat, "in_water": in_water, "head_in_water": head_in_water,
		"contact_damage": contact, "contact_cause": cause, "sky": sky, "biome": biome_id,
		"biome_temp": biome_temp,
	}


## Открытость небу 0..15 по 5 вертикальным лучам (над головой и в 2 блоках вокруг) длиной
## SHELTER_RAY: крыша, скала над головой и пещера дают укрытие. Свет секций не читаем —
## он лежит в 3D-текстурах на видеокарте, а чтение оттуда остановило бы кадр.
func sky_exposure(x: float, y: float, z: float) -> int:
	var reg := world.registry
	var open := 0
	for o: Vector2i in [Vector2i.ZERO, Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var bx := floori(x) + o.x
		var bz := floori(z) + o.y
		var blocked := false
		for dy in range(0, SHELTER_RAY):
			var b := world.get_block(bx, floori(y) + dy, bz)
			if b > 0 and reg.block_opaque[b] == 1:
				blocked = true
				break
		if not blocked:
			open += 1
	return roundi(15.0 * open / 5.0)


## То же, что heat_around, но по секциям чанков: у каждой секции один раз (после изменения)
## запоминается список тёплых клеток, секции без них пропускаются целиком.
func _heat_scan(px: float, py: float, pz: float, radius: float) -> float:
	var table := world.registry.block_heat
	var r := int(ceil(radius))
	var y0 := maxi(floori(py) - r, WorldConst.MIN_Y)
	var y1 := mini(floori(py) + r, WorldConst.MAX_Y - 1)
	var total := 0.0
	if _heat_cache.size() > 2048:
		_heat_cache.clear()
	for cz in range((floori(pz) - r) >> 4, ((floori(pz) + r) >> 4) + 1):
		for cx in range((floori(px) - r) >> 4, ((floori(px) + r) >> 4) + 1):
			var col: ChunkColumn = world.chunks.columns.get(Vector2i(cx, cz))
			if col == null:
				continue
			for si in range(WorldConst.section_index(y0), WorldConst.section_index(y1) + 1):
				var sec := col.sections[si]
				if sec == null:
					continue
				var by := WorldConst.section_base_y(si)
				if sec.is_uniform():
					if sec.uniform < table.size() and table[sec.uniform] > 0.0:
						# Сплошная лава: ближайшая точка секции.
						var q := Vector3(clampf(px, cx << 4, (cx << 4) + 16), clampf(py, by, by + 16), clampf(pz, cz << 4, (cz << 4) + 16))
						total += heat_falloff(table[sec.uniform], q.distance_to(Vector3(px, py, pz)), radius) * 3.0
					continue
				for idx in _hot_cells(sec, table):
					var b := sec.blocks[idx]
					var d := Vector3((cx << 4) + (idx & 15) + 0.5 - px, by + (idx >> 8) + 0.5 - py, (cz << 4) + ((idx >> 4) & 15) + 0.5 - pz).length()
					total += heat_falloff(table[b], d, radius)
	return minf(total, 45.0)


## Индексы клеток секции с тёплыми блоками (кэш по версии секции).
func _hot_cells(sec: ChunkSection, table: PackedFloat32Array) -> PackedInt32Array:
	var key := sec.get_instance_id()
	var c: Variant = _heat_cache.get(key)
	if c != null and int(c[0]) == sec.version:
		return c[1]
	var out := PackedInt32Array()
	var blocks := sec.blocks
	var n := table.size()
	for i in blocks.size():
		var b := blocks[i]
		if b < n and table[b] > 0.0:
			out.append(i)
	_heat_cache[key] = [sec.version, out]
	return out
