class_name Spoilage
extends RefCounted
## Порча еды (раздел 7 ТЗ, этап 9) без мира. Свежесть — data["freshness"] 0…1 ступенями по
## 1/STEPS, чтобы одинаковая еда продолжала складываться в стопки. За hours часов при
## множителе скорости rate стопка стареет на hours·rate / (spoil_days·24) свежести; дробная
## ступень выпадает с соответствующей вероятностью — в среднем ровно столько, сколько нужно.
## Скорость по температуре хранения: каждые 10 °C ниже 20 °C — вдвое медленнее (погреб под
## землёй ~10 °C — вдвое; зимой на морозе — в 8 раз), ледник (хранилище с тегом cooling) — ещё
## в COOLING раз. Засолка, копчение, сушка — отдельные блюда с долгим spoil_days.

const STEPS := 20
const COOLING := 0.2
const RATE_MIN := 0.06
const RATE_MAX := 2.5


## Множитель скорости порчи при температуре temp (°C); cooling — ледник.
static func rate(temp: float, cooling: bool = false) -> float:
	var r := clampf(pow(2.0, (temp - 20.0) / 10.0), RATE_MIN, RATE_MAX)
	return r * (COOLING if cooling else 1.0)


static func freshness(s: ItemStack) -> float:
	return float(s.data.get("freshness", 1.0))


## Состарить стопку. true — свежесть изменилась.
static func age(s: ItemStack, def: ItemDef, hours: float, mult: float, rng: RandomNumberGenerator) -> bool:
	if s == null or def == null or hours <= 0.0:
		return false
	var days := float(def.food.get("spoil_days", 0.0))
	if days <= 0.0:
		return false
	var f := freshness(s)
	if f <= 0.0:
		return false
	var steps := hours * mult / (days * 24.0) * STEPS
	var whole := floori(steps)
	if rng.randf() < steps - whole:
		whole += 1
	if whole <= 0:
		return false
	var nf := maxf(0.0, roundf(f * STEPS - whole) / STEPS)
	s.data["freshness"] = nf
	return true


## Подпись свежести для подсказки.
static func label(f: float) -> String:
	if f <= 0.0:
		return "испорчено"
	if f < PlayerVitals.SPOILED:
		return "портится (%d%%)" % roundi(f * 100.0)
	return "%d%%" % roundi(f * 100.0)
