class_name WorldSeed
extends RefCounted
## Сид мира из текста: целое число берётся как есть, остальное хэшируется FNV-1a (64 бит).
## Не String.hash(): его реализация может поменяться между версиями движка, а сид — навсегда.


static func from_text(text: String) -> int:
	var t := text.strip_edges()
	if t.is_valid_int():
		return t.to_int()
	var h := -3750763034362895579  # 0xcbf29ce484222325 как знаковое int64
	for byte in t.to_utf8_buffer():
		h = (h ^ byte) * 1099511628211
	return h


## Независимый 31-битный подсид для отдельного шума (FastNoiseLite принимает int32).
static func derive(world_seed: int, salt: int) -> int:
	var h := world_seed ^ (salt * -7046029254386353131)  # 0x9E3779B97F4A7C15
	h = (h ^ (h >> 31)) * -4658895280553007687     # 0xBF58476D1CE4E5B9
	h = h ^ (h >> 29)
	return h & 0x7fffffff


## Случайный сид для кнопки «случайный».
static func random() -> int:
	return randi() | (randi() << 32)
