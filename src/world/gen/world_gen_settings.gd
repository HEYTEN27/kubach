class_name WorldGenSettings
extends RefCounted
## Параметры мира с экрана создания (раздел 2.2). Хранятся в world.json → "worldgen".
## Генератор использует тип мира, размер биомов, пещеры, руды и уровень моря; остальное
## (деревни, лагеря, бандиты, сезоны, сутки, сложность) — для следующих этапов.

const DIFFICULTIES: Array[StringName] = [&"peaceful", &"easy", &"normal", &"hard", &"hardcore"]
const SEASONS: Array[StringName] = [&"spring", &"summer", &"autumn", &"winter"]

var world_type: StringName = &"normal"
## Множитель размера биомов (ползунок 0.5–4).
var biome_size := 1.0
## Частота пещер (0 — нет пещер, 1 — по умолчанию, 2 — вдвое больше).
var caves := 1.0
## Обилие руд (0 — нет руд, 1 — по умолчанию, 3 — втрое больше).
var ores := 1.0
var sea_level := 64
var villages := 1.0
var tribe_camps := 1.0
var bandits := 1.0
## Длина сезона в игровых днях (7–56).
var season_length := 28
## Длина суток в минутах (10–60).
var day_length := 24
var difficulty: StringName = &"normal"
var start_season: StringName = &"summer"


static func from_dict(d: Dictionary) -> WorldGenSettings:
	var s := WorldGenSettings.new()
	s.world_type = StringName(d.get("world_type", "normal"))
	s.biome_size = clampf(float(d.get("biome_size", 1.0)), 0.25, 8.0)
	s.caves = clampf(float(d.get("caves", 1.0)), 0.0, 3.0)
	s.ores = clampf(float(d.get("ores", 1.0)), 0.0, 3.0)
	s.sea_level = clampi(int(d.get("sea_level", 64)), 32, 96)
	s.villages = clampf(float(d.get("villages", 1.0)), 0.0, 3.0)
	s.tribe_camps = clampf(float(d.get("tribe_camps", 1.0)), 0.0, 3.0)
	s.bandits = clampf(float(d.get("bandits", 1.0)), 0.0, 3.0)
	s.season_length = clampi(int(d.get("season_length", 28)), 7, 56)
	s.day_length = clampi(int(d.get("day_length", 24)), 10, 60)
	var diff := StringName(d.get("difficulty", "normal"))
	s.difficulty = diff if diff in DIFFICULTIES else &"normal"
	var season := StringName(d.get("start_season", "summer"))
	s.start_season = season if season in SEASONS else &"summer"
	return s


func to_dict() -> Dictionary:
	return {
		"world_type": String(world_type), "biome_size": biome_size, "caves": caves, "ores": ores,
		"sea_level": sea_level, "villages": villages, "tribe_camps": tribe_camps, "bandits": bandits,
		"season_length": season_length, "day_length": day_length, "difficulty": String(difficulty),
		"start_season": String(start_season),
	}


func season_index() -> int:
	return SEASONS.find(start_season)
