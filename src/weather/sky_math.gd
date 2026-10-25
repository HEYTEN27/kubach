class_name SkyMath
extends RefCounted
## Небесная механика (раздел 3.1 ТЗ) без узлов: восход и закат по сезону (длина дня
## плавно меняется в течение года между значениями data/seasons.json для середины сезонов),
## высота и азимут солнца, фаза луны (data/sky.json → moon_cycle_days) и её положение.
## Летом солнце встаёт рано и поднимается высоко, зимой день короткий и солнце низкое.

const SEASONS: Array[StringName] = [&"spring", &"summer", &"autumn", &"winter"]
## Наибольшая высота солнца при самом коротком и самом длинном дне.
const ELEV_SHORT := 18.0
const ELEV_LONG := 62.0
const DAY_SHORT := 7.0
const DAY_LONG := 18.0
const NIGHT_DEPTH := 28.0


## Доля года 0…1 (0 — начало весны) для дня day при стартовом сезоне и длине сезона.
static func year_fraction(day: int, minute: float, start_season: int, season_length: int) -> float:
	var days := float(day - 1) + minute / 1440.0
	var len := maxf(1.0, float(season_length))
	return fposmod((float(start_season) * len + days) / (4.0 * len), 1.0)


## Восход и закат (часы) в долю года t: косинусная интерполяция между серединами сезонов.
## seasons — 4 пары [восход, закат] в порядке весна, лето, осень, зима.
static func day_window(t: float, seasons: Array) -> Vector2:
	if seasons.size() != 4:
		return Vector2(6.0, 21.0)
	# Середина сезона i — в t = (i + 0.5) / 4.
	var pos := fposmod(t * 4.0 - 0.5, 4.0)
	var i := int(floor(pos)) % 4
	var j := (i + 1) % 4
	var k: float = pos - floor(pos)
	var s := 0.5 - 0.5 * cos(k * PI)
	var a: Vector2 = seasons[i]
	var b: Vector2 = seasons[j]
	return a.lerp(b, s)


static func is_night(hour: float, window: Vector2) -> bool:
	return hour < window.x or hour >= window.y


## Солнце: Vector2(высота°, азимут°). Днём — дуга от восхода до заката, ночью — под горизонтом.
## Азимут: 90 — восток (восход), 180 — юг (полдень), 270 — запад (закат).
static func sun(hour: float, window: Vector2) -> Vector2:
	var length := window.y - window.x
	var peak := lerpf(ELEV_SHORT, ELEV_LONG, clampf((length - DAY_SHORT) / (DAY_LONG - DAY_SHORT), 0.0, 1.0))
	if hour >= window.x and hour < window.y:
		var t := (hour - window.x) / length
		return Vector2(sin(t * PI) * peak, 90.0 + t * 180.0)
	var night := 24.0 - length
	var n := fposmod(hour - window.y, 24.0) / night
	return Vector2(-sin(n * PI) * NIGHT_DEPTH, 270.0 + n * 180.0)


## Фаза луны 0…1: 0 — новолуние, 0.5 — полнолуние.
static func moon_phase(day: int, minute: float, cycle_days: float) -> float:
	var days := float(day - 1) + minute / 1440.0
	return fposmod(days / maxf(1.0, cycle_days) + 0.5, 1.0)


## Освещённая доля диска 0…1.
static func moon_illumination(phase: float) -> float:
	return 0.5 - 0.5 * cos(phase * TAU)


## Луна: Vector2(высота°, азимут°). Восходит на phase·24 ч позже солнца: полная — на закате,
## новая — вместе с солнцем (днём, не видна).
static func moon(hour: float, window: Vector2, phase: float) -> Vector2:
	var rise := fposmod(window.x + phase * 24.0, 24.0)
	var t := fposmod(hour - rise, 24.0) / 12.4
	if t <= 1.0:
		return Vector2(sin(t * PI) * 48.0, 90.0 + t * 180.0)
	var n := (fposmod(hour - rise, 24.0) - 12.4) / (24.0 - 12.4)
	return Vector2(-sin(n * PI) * NIGHT_DEPTH, 270.0 + n * 180.0)


## Направление НА светило в мировых осях (−Z — север, +X — восток): для шейдера неба.
static func direction(elev_az: Vector2) -> Vector3:
	var e := deg_to_rad(elev_az.x)
	var a := deg_to_rad(elev_az.y)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e)).normalized()


## Пары [восход, закат] сезонов из реестра (порядок SEASONS).
static func season_windows(reg: ContentRegistry) -> Array:
	var out := []
	for s in SEASONS:
		if reg.has_entry("seasons", s):
			var e := reg.get_entry("seasons", s)
			out.append(Vector2(float(e["sunrise"]), float(e["sunset"])))
	return out
