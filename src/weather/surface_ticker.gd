class_name SurfaceTicker
extends RefCounted
## Сезонная поверхность (раздел 3.2 ТЗ): снег копится слоями 1–8, в оттепель тает, озёра и
## реки замерзают и оттаивают. Как «случайные тики» блоков: за тик берётся SAMPLES случайных
## клеток поверхности вокруг игрока, и к верхнему блоку применяется правило с шансом по
## интенсивности снегопада и температуре. Изменений за тик не больше MAX_CHANGES.
## Снег и лёд не меняют света (фильтр как у воздуха и воды) — колонна только перемешивается.

const SAMPLES := 48
const MAX_CHANGES := 12
const RADIUS := 56
const MELT_ABOVE := 1.5
const FREEZE_BELOW := -2.0
const THAW_ABOVE := 2.0

var world: World
var rng := RandomNumberGenerator.new()
## Уровень снега 1…8 → числовой ID блока (0 — нет).
var layers := PackedInt32Array()
var water := 0
var ice := 0
var _layer_of := {}   # num блока → уровень


func _init(p_world: World) -> void:
	world = p_world
	rng.randomize()
	var reg := world.registry
	layers.resize(9)
	layers[1] = maxi(0, reg.block_num(&"snow_layer"))
	for k in range(2, 9):
		layers[k] = maxi(0, reg.block_num(StringName("snow_layer_%d" % k)))
	for k in range(1, 9):
		if layers[k] > 0:
			_layer_of[layers[k]] = k
	water = maxi(0, reg.block_num(&"water"))
	ice = maxi(0, reg.block_num(&"ice"))


func snow_level(b: int) -> int:
	return int(_layer_of.get(b, 0))


## Один тик вокруг (cx, cz). w — значения погоды (WeatherSim.values), temp_at(x, y, z) -> °C,
## melt_bonus — весеннее таяние сезона. hours — игровые часы с прошлого тика.
## Возвращает число изменённых клеток.
func tick(cx: float, cz: float, w: Dictionary, temp_at: Callable, hours: float, melt_bonus: float = 0.0) -> int:
	var changes := 0
	var snow := float(w.get("snow", 0.0))
	var rain := float(w.get("rain", 0.0))
	for i in SAMPLES:
		if changes >= MAX_CHANGES:
			break
		var x := floori(cx) + rng.randi_range(-RADIUS, RADIUS)
		var z := floori(cz) + rng.randi_range(-RADIUS, RADIUS)
		var col: ChunkColumn = world.chunks.columns.get(Vector2i(x >> 4, z >> 4))
		if col == null:
			continue
		var y := col.top_block_y(x & 15, z & 15)
		if y < WorldConst.MIN_Y:
			continue
		var b := col.get_block(x & 15, y, z & 15)
		var t: float = temp_at.call(x, y + 1, z)
		if apply(x, y, z, b, t, snow, rain, hours, melt_bonus):
			changes += 1
	return changes


## Правило для верхнего блока b в (x, y, z). true — блок изменён.
func apply(x: int, y: int, z: int, b: int, temp: float, snow: float, rain: float, hours: float,
		melt_bonus: float = 0.0) -> bool:
	var reg := world.registry
	var lvl := snow_level(b)
	# Снегопад в мороз: слой растёт или ложится новый.
	if snow > 0.02 and temp < WeatherSim.SNOW_BELOW:
		var p := 1.0 - pow(1.0 - 0.9 * snow, hours * 8.0)
		if rng.randf() >= p:
			return false
		if lvl > 0:
			if lvl < 8:
				return world.set_block(x, y, z, layers[lvl + 1])
			return false
		if b == water or reg.block_render[b] == BlockDef.RENDER_LIQUID:
			return false
		var top_ok := reg.block_solid[b] == 1 and reg.block_shape[b] == BlockDef.SHAPE_CUBE and reg.block_model[b] == 0
		if top_ok and world.get_block(x, y + 1, z) == 0:
			return world.set_block(x, y + 1, z, layers[1])
		return false
	# Оттепель: слой тает (дождь и весна — быстрее).
	if lvl > 0 and temp > MELT_ABOVE:
		var rate := (temp - MELT_ABOVE) * 0.05 + rain * 0.5 + melt_bonus
		if rng.randf() < 1.0 - pow(1.0 - clampf(rate, 0.0, 0.95), hours * 8.0):
			return world.set_block(x, y, z, layers[lvl - 1] if lvl > 1 else 0)
		return false
	# Замерзание воды и ледоход.
	if b == water and temp < FREEZE_BELOW and world.get_block(x, y + 1, z) == 0:
		if rng.randf() < 1.0 - pow(1.0 - clampf((FREEZE_BELOW - temp) * 0.05, 0.0, 0.9), hours * 8.0):
			return world.set_block(x, y, z, ice)
		return false
	if b == ice and temp > THAW_ABOVE:
		if rng.randf() < 1.0 - pow(1.0 - clampf((temp - THAW_ABOVE) * 0.04, 0.0, 0.9), hours * 8.0):
			return world.set_block(x, y, z, water)
	return false
