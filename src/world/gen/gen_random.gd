class_name GenRandom
extends RefCounted
## Детерминированные хэши для генерации. Результат зависит только от аргументов, а не от
## порядка вызовов — поэтому блок на стыке колонн одинаков, какую бы колонну ни строили первой.


## 64-битное перемешивание (splitmix64).
static func mix(h: int) -> int:
	h = (h ^ (h >> 30)) * -4658895280553007687   # 0xBF58476D1CE4E5B9
	h = (h ^ (h >> 27)) * -7723592293110705685   # 0x94D049BB133111EB
	return h ^ (h >> 31)


static func hash2(seed_value: int, a: int, b: int, salt: int = 0) -> int:
	return mix(mix(mix(seed_value ^ (salt * -7046029254386353131)) + a) + b)


static func hash3(seed_value: int, a: int, b: int, c: int, salt: int = 0) -> int:
	return mix(hash2(seed_value, a, b, salt) + c)


## Число в [0, 1) из хэша.
static func unit(h: int) -> float:
	return float((h >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0


static func unit2(seed_value: int, a: int, b: int, salt: int = 0) -> float:
	return unit(hash2(seed_value, a, b, salt))


static func unit3(seed_value: int, a: int, b: int, c: int, salt: int = 0) -> float:
	return unit(hash3(seed_value, a, b, c, salt))


## Генератор последовательности, засеянный хэшем (для формы одной залежи или дерева).
static func rng(h: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = h
	return r
