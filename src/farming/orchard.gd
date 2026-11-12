class_name Orchard
extends RefCounted
## Чистая логика садов (этап 9): какой вид листвы плодового дерева должен быть в клетке в данный
## сезон и как растёт саженец. Листва плодовых — три блока: обычная (0), в цвету (1), с плодами (2).
## Правило идемпотентно (можно применять сколько угодно раз за сезон):
## - весна: плоды опадают, доля BLOSSOM_SHARE клеток (по хэшу клетки) зацветает;
## - сезон плодов: цвет становится плодами; пустая листва из доли FRUIT_SHARE дозревает
##   постепенно (шанс RIPEN_PER_DAY в сутки) — так собранные плоды отрастают к следующим дням;
## - прочие сезоны: плоды опадают; цвет остаётся, если сезон плодов в этом году ещё впереди.

const SEASONS: Array[StringName] = [&"spring", &"summer", &"autumn", &"winter"]
const BLOSSOM_SHARE := 0.45
const FRUIT_SHARE := 0.3
const RIPEN_PER_DAY := 0.35
## Соль хэша клетки листвы.
const SALT := 71


## Маска сезонов плодов (бит на сезон) из списка id.
static func season_mask(seasons: Array) -> int:
	var m := 0
	for s: Variant in seasons:
		var i := SEASONS.find(StringName(s))
		if i >= 0:
			m |= 1 << i
	return m


## Новый вид листвы (0/1/2) из текущего v в сезоне s (0…3). h — хэш клетки 0…1, mask — сезоны
## плодов, ripen — случайное 0…1 для дозревания, days — сколько суток прошло с прошлой проверки.
static func next_variant(v: int, s: int, h: float, mask: int, ripen: float, days: float) -> int:
	if s == 0:
		if v == 2:
			return 1 if h < BLOSSOM_SHARE else 0
		if v == 0 and h < BLOSSOM_SHARE:
			return 1
		return v
	if mask & (1 << s):
		if v == 1:
			return 2
		if v == 0 and h < FRUIT_SHARE and ripen < 1.0 - pow(1.0 - RIPEN_PER_DAY, clampf(days, 0.0, 30.0)):
			return 2
		return v
	if v == 2:
		return 0
	if v == 1 and (mask >> (s + 1)) == 0:
		return 0
	return v


## Прирост доли роста саженца за hours часов (0, если зима или нет почвы).
static func sapling_growth(grow_days: float, hours: float, season: int, on_soil: bool) -> float:
	if not on_soil or season == 3 or grow_days <= 0.0:
		return 0.0
	return hours / (grow_days * 24.0)
