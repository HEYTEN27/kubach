class_name AnimalLife
extends RefCounted
## Чистая логика жизни домашних животных (этап 9): взросление, кормление, любовь и детёныши,
## продукция (яйца, молоко, шерсть, навоз), добыча при забое. Определение вида — запись
## data/animals.json (словарь после Registry). Время — абсолютные игровые минуты.

## Сколько минут длится «любовь» после кормления взрослого.
const LOVE_MINUTES := 60.0
## Сколько минут после последней найденной воды животное считается напоенным.
const WATER_MINUTES := 24.0 * 60.0
## Масштаб детёныша.
const BABY_SCALE := 0.55


static func is_adult(a: Animal, def: Dictionary, now: float) -> bool:
	return now - a.born >= float(def.get("adult_days", 3.0)) * 1440.0


static func is_fed(a: Animal, now: float) -> bool:
	return now < a.fed_until


static func is_watered(a: Animal, now: float) -> bool:
	return a.water_seen >= 0.0 and now - a.water_seen < WATER_MINUTES


## Ест ли вид этот предмет (id или #тег из поля food).
static func accepts(def: Dictionary, item: ItemDef) -> bool:
	if item == null:
		return false
	for f: Variant in def.get("food", []):
		var s := String(f)
		if s.begins_with("#"):
			if item.tags.has(s.substr(1)):
				return true
		elif StringName(s) == item.id:
			return true
	return false


## Накормить. Сытый взрослый, отдохнувший после прошлых родов, «влюбляется». Возвращает true,
## если животное съело (голодное или влюбиться готово).
static func feed(a: Animal, def: Dictionary, now: float) -> bool:
	var hungry := not is_fed(a, now)
	var can_love := is_adult(a, def, now) and now >= a.breed_after and now >= a.love_until
	if not hungry and not can_love:
		return false
	a.fed_until = maxf(a.fed_until, now) + float(def.get("fed_hours", 24.0)) * 60.0
	if can_love:
		a.love_until = now + LOVE_MINUTES
	return true


static func in_love(a: Animal, now: float) -> bool:
	return now < a.love_until


static func can_breed(a: Animal, b: Animal, def: Dictionary, now: float) -> bool:
	return a != b and a.kind == b.kind and in_love(a, now) and in_love(b, now) \
			and is_adult(a, def, now) and is_adult(b, def, now)


## Родители отдыхают breed_days; возвращает детёныша (место — между родителями).
static func breed(a: Animal, b: Animal, def: Dictionary, now: float) -> Animal:
	var rest := now + float(def.get("breed_days", 2.0)) * 1440.0
	for p: Animal in [a, b]:
		p.love_until = 0.0
		p.breed_after = rest
	var c := Animal.new()
	c.kind = a.kind
	c.id = a.id
	c.x = (a.x + b.x) * 0.5
	c.y = maxf(a.y, b.y)
	c.z = (a.z + b.z) * 0.5
	c.yaw = a.yaw
	c.born = now
	c.fed_until = now + 12.0 * 60.0
	c.health = float(def.get("health", 10.0)) * 0.5
	init_products(c, def, now)
	return c


## Сроки продукции новорождённого/появившегося: каждая — через свой период.
static func init_products(a: Animal, def: Dictionary, now: float) -> void:
	var prods: Array = def.get("products", [])
	a.next.resize(prods.size())
	for i in prods.size():
		var p: Dictionary = prods[i]
		# Шерсть у появившегося взрослого уже есть; остальное — через период.
		a.next[i] = now if String(p.get("method", "")) == "shear" else now + float(p.get("every_hours", 24.0)) * 60.0


## Можно ли сейчас получить продукт i вручную (молоко — сытое и напоенное, шерсть — отросла).
static func can_take(a: Animal, def: Dictionary, i: int, now: float) -> bool:
	var prods: Array = def.get("products", [])
	if i < 0 or i >= prods.size() or not is_adult(a, def, now):
		return false
	if a.next.size() <= i:
		init_products(a, def, now)
	var p: Dictionary = prods[i]
	if now < a.next[i]:
		return false
	if String(p.get("method", "")) == "shear":
		return true
	return is_fed(a, now) and (is_watered(a, now) or not bool(p.get("needs_water", true)))


## Индекс продукта с методом method или −1.
static func product_index(def: Dictionary, method: String) -> int:
	var prods: Array = def.get("products", [])
	for i in prods.size():
		if String(prods[i].get("method", "")) == method:
			return i
	return -1


## Забрать продукт i (milk/shear): [id, количество]; срок — заново.
static func take(a: Animal, def: Dictionary, i: int, now: float, rng: RandomNumberGenerator) -> Array:
	var p: Dictionary = def["products"][i]
	a.next[i] = now + float(p.get("every_hours", 24.0)) * 60.0
	return [StringName(p["item"]), rng.randi_range(int(p.get("min", 1)), maxi(int(p.get("min", 1)), int(p.get("max", 1))))]


## Сама кладёт/роняет (lay, drop): продукты, срок которых настал. Сытое (и напоенное, если нужно)
## даёт продукт всегда, голодное — с шансом unfed_chance. За один вызов — не больше одного раза
## на продукт (долгий досчёт не засыпает землю яйцами). Возвращает [[id, n, метод], …].
static func due(a: Animal, def: Dictionary, now: float, rng: RandomNumberGenerator) -> Array:
	var out := []
	var prods: Array = def.get("products", [])
	if a.next.size() < prods.size():
		init_products(a, def, now)
	if not is_adult(a, def, now):
		return out
	for i in prods.size():
		var p: Dictionary = prods[i]
		var m := String(p.get("method", ""))
		if (m != "lay" and m != "drop") or now < a.next[i]:
			continue
		a.next[i] = now + float(p.get("every_hours", 24.0)) * 60.0
		var ok := is_fed(a, now) and (is_watered(a, now) or not bool(p.get("needs_water", true)))
		if not ok and rng.randf() >= float(p.get("unfed_chance", 0.0)):
			continue
		out.append([StringName(p["item"]), rng.randi_range(int(p.get("min", 1)), maxi(int(p.get("min", 1)), int(p.get("max", 1)))), m])
	return out


## Добыча при забое: [[id, n], …]; детёныш даёт вдвое меньше (не меньше одного основного).
static func drops(def: Dictionary, adult: bool, rng: RandomNumberGenerator) -> Array:
	var out := []
	for d: Dictionary in def.get("drops", []):
		if rng.randf() > float(d.get("chance", 1.0)):
			continue
		var n := rng.randi_range(int(d.get("min", 1)), maxi(int(d.get("min", 1)), int(d.get("max", 1))))
		if not adult:
			n = n / 2 if out.size() > 0 else maxi(1, n / 2)
		if n > 0:
			out.append([StringName(d["id"]), n])
	return out
