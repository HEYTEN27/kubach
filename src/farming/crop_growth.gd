class_name CropGrowth
extends RefCounted
## Рост культур (раздел 8 ТЗ, этап 9) без мира: скорость по условиям, стадия по прогрессу,
## увядание, урожай. Условия — словарь, который собирает FarmSystem:
## { season: StringName, temp: °C, wet: bool, fert: сила удобрения, weeds: сорняков рядом,
##   greenhouse: bool, dark: bool (крыша над культурой), near_water: bool }.
## Состояние культуры — словарь сущности блока: { crop, p (0…1), bad (часы в плохих условиях) }.

const WEED_PENALTY := 0.15
const MIN_WEED_FACTOR := 0.3
const FERT_BONUS := 0.5
const DRY_PENALTY := 0.8
const GREENHOUSE_WARMTH := 10.0


## Можно ли расти сейчас: сезон (теплица — всегда), температура, свет, вода для риса.
static func can_grow(c: Dictionary, cond: Dictionary) -> bool:
	if cond.get("dark", false):
		return false
	if not cond.get("greenhouse", false):
		var seasons: Array = c.get("seasons", [])
		if not seasons.is_empty() and not seasons.has(String(cond.get("season", "summer"))):
			return false
	var t := float(cond.get("temp", 15.0))
	if t < float(c.get("temp_min", 4.0)) or t > float(c.get("temp_max", 32.0)):
		return false
	if c.get("on_water", false) and not cond.get("near_water", false):
		return false
	return true


## Прогресс за игровой час (доля от посадки до урожая).
static func rate_per_hour(c: Dictionary, cond: Dictionary) -> float:
	if not can_grow(c, cond):
		return 0.0
	var r := 1.0 / (maxf(0.1, float(c.get("grow_days", 5.0))) * 24.0)
	if not cond.get("wet", false):
		r *= 1.0 - DRY_PENALTY * float(c.get("water", 0.5))
	r *= 1.0 + FERT_BONUS * float(cond.get("fert", 0.0))
	r *= maxf(MIN_WEED_FACTOR, 1.0 - WEED_PENALTY * float(cond.get("weeds", 0)))
	return r


## Стадия (0 … stages−1) по прогрессу: последняя — только при полном созревании.
static func stage_of(p: float, stages: int) -> int:
	if p >= 1.0:
		return stages - 1
	return clampi(floori(p * float(stages - 1)), 0, stages - 2)


## Прогресс начала стадии (для многолетников после сбора).
static func progress_of(stage: int, stages: int) -> float:
	return clampf(float(stage) / float(maxi(1, stages - 1)), 0.0, 1.0)


## Шаг роста на hours часов. Возвращает "grow", "ripe" (только что созрела), "wither" или "".
## Многолетники вне сезона и в холод не вянут — спят до весны.
static func advance(e: Dictionary, c: Dictionary, cond: Dictionary, hours: float) -> String:
	var was_ripe := float(e.get("p", 0.0)) >= 1.0
	if can_grow(c, cond):
		e["bad"] = maxf(0.0, float(e.get("bad", 0.0)) - hours * 0.5)
		if was_ripe:
			return ""
		e["p"] = minf(1.0, float(e.get("p", 0.0)) + rate_per_hour(c, cond) * hours)
		return "ripe" if float(e["p"]) >= 1.0 else "grow"
	if c.get("perennial", false) and not cond.get("dark", false):
		return ""
	e["bad"] = float(e.get("bad", 0.0)) + hours
	if float(e["bad"]) >= float(c.get("wither_days", 3.0)) * 24.0:
		return "wither"
	return ""


## Урожай: [[id, count], …]. ripe — спелая; hybrid — культура-партнёр для гибрида рядом;
## replant — сбор ПКМ с пересадкой (одно семя уходит обратно в землю).
static func harvest(c: Dictionary, stage: int, rng: RandomNumberGenerator, hybrid_partner: StringName = &"",
		replant: bool = false) -> Array:
	var out := []
	var stages := int(c.get("stages", 5))
	var seeds := StringName("%s_seeds" % c["id"])
	if stage < stages - 1:
		if not replant:
			out.append([seeds, 1])
		return out
	var n := rng.randi_range(int(c.get("produce_min", 1)), int(c.get("produce_max", 2)))
	if n > 0:
		out.append([StringName(c["produce"]), n])
	if not c.get("perennial", false):
		var sn := rng.randi_range(int(c.get("seeds_min", 1)), int(c.get("seeds_max", 2))) - (1 if replant else 0)
		if sn > 0:
			out.append([seeds, sn])
	for h: Dictionary in c.get("hybrids", []):
		if StringName(h["with"]) == hybrid_partner and rng.randf() < float(h.get("chance", 0.04)):
			out.append([StringName("%s_seeds" % h["child"]), 1])
	return out
