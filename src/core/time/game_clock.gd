class_name GameClock
extends RefCounted
## Игровое время (раздел 2.2: длина суток 10–60 минут, по умолчанию 24): день и минута суток,
## сезон по дню, восход и закат по сезону (этап 7, SkyMath и data/seasons.json; без данных —
## постоянные 6:00 и 21:00).

const SEASONS: Array[StringName] = [&"spring", &"summer", &"autumn", &"winter"]
const SEASON_NAMES := { &"spring": "Весна", &"summer": "Лето", &"autumn": "Осень", &"winter": "Зима" }

const MINUTES_PER_DAY := 1440.0
const NIGHT_START := 21.0
const NIGHT_END := 6.0
const START_HOUR := 8.0

var day := 1
var minute := START_HOUR * 60.0
## Длина игровых суток в реальных минутах (настройка мира).
var day_length_min := 24.0
## Сезон первого дня (индекс в SEASONS) и длина сезона в днях (настройки мира).
var start_season := 1
var season_length := 28
## Восход и закат середины каждого сезона: 4 × Vector2 (SkyMath.season_windows). Пусто — постоянные.
var windows: Array = []


func _init(p_day_length: float = 24.0) -> void:
	day_length_min = clampf(p_day_length, 1.0, 600.0)


## Игровых часов в одной реальной секунде.
func hours_per_second() -> float:
	return 24.0 / (day_length_min * 60.0)


## Продвинуть время на real_seconds реальных секунд; возвращает прошедшие игровые часы.
func advance(real_seconds: float) -> float:
	var hours := real_seconds * hours_per_second()
	advance_hours(hours)
	return hours


func advance_hours(hours: float) -> void:
	minute += hours * 60.0
	while minute >= MINUTES_PER_DAY:
		minute -= MINUTES_PER_DAY
		day += 1


func hour() -> float:
	return minute / 60.0


func is_night() -> bool:
	return SkyMath.is_night(hour(), day_window())


## Восход и закат сегодня (часы).
func day_window() -> Vector2:
	if windows.size() != 4:
		return Vector2(NIGHT_END, NIGHT_START)
	return SkyMath.day_window(year_fraction(), windows)


func sunrise() -> float:
	return day_window().x


## Доля года 0…1 (0 — начало весны).
func year_fraction() -> float:
	return SkyMath.year_fraction(day, minute, start_season, season_length)


## Абсолютное время в игровых минутах с начала мира.
func total_minutes() -> float:
	return float(day - 1) * MINUTES_PER_DAY + minute


## Сколько часов до ближайшего наступления часа target (0…24).
func hours_until(target: float) -> float:
	var d := target - hour()
	return d if d > 0.0 else d + 24.0


## Текущий сезон: от стартового, сменяется каждые season_length дней.
func season() -> StringName:
	return SEASONS[(start_season + (day - 1) / maxi(1, season_length)) % 4]


## День внутри текущего сезона (1…season_length).
func season_day() -> int:
	return (day - 1) % maxi(1, season_length) + 1


## Строка времени: «14:05» или «2:05 PM».
func time_text(h24: bool = true) -> String:
	var hh := int(minute) / 60
	var mm := int(minute) % 60
	if h24:
		return "%02d:%02d" % [hh, mm]
	var h12 := hh % 12
	return "%d:%02d %s" % [12 if h12 == 0 else h12, mm, "AM" if hh < 12 else "PM"]


func to_dict() -> Dictionary:
	return { "day": day, "minute": minute }


func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	minute = clampf(float(d.get("minute", START_HOUR * 60.0)), 0.0, MINUTES_PER_DAY - 0.01)
