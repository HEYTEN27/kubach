class_name WeatherSim
extends RefCounted
## Погода (раздел 3.3 ТЗ) без узлов: текущий тип из data/weather.json, сколько ему осталось,
## плавный переход от прошлого типа (sky.change_minutes), ветер (направление медленно
## гуляет, сила — в пределах типа). Следующий тип выбирается по весам с учётом климата:
## ключей weather биома под игроком, сезона (множители data/seasons.json) и температуры
## (снег только в мороз, дождь — только выше нуля; осадки сами меняются дождь ↔ снег).
## Случайность — от сида мира и номера смены: одинаковые условия дают одинаковую погоду.

## Ключи, которые есть везде (ясно, облачно, пасмурно).
const ALWAYS := ["clear", "cloudy", "overcast"]
const SNOW_BELOW := 0.5
const RAIN_ABOVE := 2.0
const WIND_TURN_PER_HOUR := 0.35

var types := {}           # StringName → запись data/weather.json
var seasons := {}         # StringName → запись data/seasons.json
var change_minutes := 25.0
var world_seed := 0

var current: StringName = &"clear"
var previous: StringName = &"clear"
## Часов до смены и сколько прошло с начала текущего (для перехода).
var left_hours := 6.0
var since_hours := 10.0
var changes := 0
## Ветер: угол (рад, 0 — с запада на восток) и сила 0…1.
var wind_angle := 0.8
var wind_strength := 0.2
var _wind_target := 0.2


func _init(reg: ContentRegistry = null, p_seed: int = 0) -> void:
	world_seed = p_seed
	if reg == null:
		return
	for e in reg.get_entries("weather"):
		types[StringName(e["id"])] = e
	for e in reg.get_entries("seasons"):
		seasons[StringName(e["id"])] = e
	if reg.has_entry("sky", &"default"):
		change_minutes = float(reg.get_entry("sky", &"default")["change_minutes"])


## Шаг: hours игровых часов. climate: { weather: Array ключей биома, season, temp (°C воздуха) }.
func advance(hours: float, climate: Dictionary) -> void:
	var left := hours
	while left > 0.0:
		var dt := minf(left, maxf(0.01, left_hours))
		left_hours -= dt
		since_hours += dt
		left -= dt
		_wind_step(dt)
		if left_hours <= 0.0:
			_next(climate)
	# Осадки не по погоде: мороз превращает дождь в снег — это делает current_values().


func _wind_step(dt: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, changes, int(since_hours * 4.0)])
	wind_angle += rng.randf_range(-1.0, 1.0) * WIND_TURN_PER_HOUR * dt
	wind_strength = move_toward(wind_strength, _wind_target, dt * 0.5)


## Выбрать следующий тип погоды.
func _next(climate: Dictionary) -> void:
	changes += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, changes, "weather"])
	var weights := allowed_weights(climate)
	var total := 0.0
	for id: StringName in weights:
		total += float(weights[id])
	var pick: StringName = &"clear"
	var r := rng.randf() * total
	for id: StringName in weights:
		r -= float(weights[id])
		if r <= 0.0:
			pick = id
			break
	previous = current
	current = pick
	var t: Dictionary = types.get(current, {})
	var dur: Dictionary = t.get("duration", {})
	left_hours = rng.randf_range(float(dur.get("min", 2.0)), float(dur.get("max", 8.0)))
	since_hours = 0.0
	_wind_target = rng.randf_range(float(t.get("wind_min", 0.1)), float(t.get("wind_max", 0.4)))


## Веса типов, которые возможны при этом климате.
func allowed_weights(climate: Dictionary) -> Dictionary:
	var keys: Array = climate.get("weather", [])
	var season: Dictionary = seasons.get(StringName(climate.get("season", "summer")), {})
	var mults: Dictionary = season.get("weather", {})
	var temp := float(climate.get("temp", 10.0))
	var out := {}
	for id: StringName in types:
		var t: Dictionary = types[id]
		var req: Array = t.get("requires", [])
		var ok := req.is_empty()
		for k in req:
			ok = ok or keys.has(k)
		var precip := String(t.get("precip", "none"))
		# Снег возможен в любой мороз, даже если в биоме нет ключа snow.
		if id == &"snow" and temp < SNOW_BELOW:
			ok = true
		if not ok:
			continue
		if precip == "snow" and temp > RAIN_ABOVE + 3.0:
			continue
		if id == &"thunderstorm" and temp < 0.0 or id == &"hail" and temp < 0.0:
			continue
		var w := float(t.get("weight", 1.0)) * float(mults.get(String(id), 1.0))
		if w > 0.0:
			out[id] = w
	if out.is_empty():
		out[&"clear"] = 1.0
	return out


## Доля перехода от прошлого типа к текущему 0…1.
func blend() -> float:
	return clampf(since_hours * 60.0 / maxf(1.0, change_minutes), 0.0, 1.0)


## Значения погоды сейчас (с переходом). temp — температура воздуха для «дождь ↔ снег».
## { cloud, rain, snow, hail, fog, dust, darkness, temp, lightning, wind, wind_dir, hail_damage, thirst }
func values(temp: float = 10.0) -> Dictionary:
	var a := _raw(previous)
	var b := _raw(current)
	var k := blend()
	var out := {}
	for key: String in b:
		out[key] = lerpf(float(a.get(key, 0.0)), float(b[key]), k)
	# Мороз: дождь идёт снегом; оттепель: снег идёт дождём.
	if temp < SNOW_BELOW and float(out["rain"]) > 0.0:
		out["snow"] = maxf(float(out["snow"]), float(out["rain"]))
		out["rain"] = 0.0
	elif temp > RAIN_ABOVE and float(out["snow"]) > 0.0:
		out["rain"] = maxf(float(out["rain"]), float(out["snow"]) * 0.8)
		out["snow"] = 0.0
	out["wind"] = clampf(wind_strength, 0.0, 1.0)
	out["wind_dir"] = Vector2(cos(wind_angle), sin(wind_angle))
	return out


func _raw(id: StringName) -> Dictionary:
	var t: Dictionary = types.get(id, {})
	var out := {}
	for key: String in ["cloud", "rain", "snow", "hail", "fog", "dust", "darkness", "temp", "lightning", "hail_damage"]:
		out[key] = float(t.get(key, 0.0))
	out["thirst"] = float(t.get("thirst", 1.0))
	return out


func name_of(id: StringName, locale: String = "ru") -> String:
	var t: Dictionary = types.get(id, {})
	return String(t.get("name", {}).get(locale, id))


## Задать погоду сразу (команда отладки, тесты).
func force(id: StringName, hours: float = 4.0) -> void:
	if not types.has(id):
		return
	previous = id
	current = id
	left_hours = hours
	since_hours = 10.0
	var t: Dictionary = types[id]
	_wind_target = float(t.get("wind_max", 0.4))
	wind_strength = _wind_target


func to_dict() -> Dictionary:
	return { "current": String(current), "previous": String(previous), "left": left_hours, "since": since_hours,
		"changes": changes, "wind_angle": wind_angle, "wind": wind_strength, "wind_target": _wind_target }


func from_dict(d: Dictionary) -> void:
	current = StringName(d.get("current", "clear"))
	previous = StringName(d.get("previous", current))
	if not types.has(current):
		current = &"clear"
	if not types.has(previous):
		previous = current
	left_hours = float(d.get("left", 6.0))
	since_hours = float(d.get("since", 10.0))
	changes = int(d.get("changes", 0))
	wind_angle = float(d.get("wind_angle", 0.8))
	wind_strength = float(d.get("wind", 0.2))
	_wind_target = float(d.get("wind_target", wind_strength))
