class_name ChunkSection
extends RefCounted
## Секция 16×16×16. Пока все блоки одинаковые, хранится одно число `uniform` —
## так глубинный камень и воздух почти не занимают память. При первой отличающейся записи
## секция разворачивается в массив `blocks` (4096 числовых ID).
##
## Снимки для потоков: в GDScript packed-массивы передаются по ссылке, поэтому set_block()
## сначала заменяет `blocks` копией и только потом пишет. Ссылка, взятая потоком мешинга
## (`var snap := section.blocks`), остаётся неизменной. Массовые записи (генератор, загрузка)
## собирают массив целиком и присваивают его, не трогая set_block().

var uniform := 0
var blocks := PackedInt32Array()
## Растёт при каждом изменении; мешер по нему понимает, что результат устарел.
var version := 0
## Все блоки — непрозрачные кубы (секция ничего не показывает и всё закрывает).
## Ложное значение безопасно: только отключает быстрый пропуск мешинга.
var all_opaque := false
## Есть блоки нестандартной формы (растения, слои) — мешеру нужен отдельный проход.
var has_special := false


static func filled(block: int) -> ChunkSection:
	var s := ChunkSection.new()
	s.uniform = block
	return s


## Пересчитывает флаги по массивам реестра (opaque[n] == 1, shape[n] != куб).
func analyze(opaque: PackedByteArray, shape: PackedByteArray) -> void:
	if blocks.is_empty():
		all_opaque = opaque[uniform] == 1
		has_special = shape[uniform] != 0
		return
	var seen := {}
	all_opaque = true
	has_special = false
	for b in blocks:
		if seen.has(b):
			continue
		seen[b] = true
		if opaque[b] != 1:
			all_opaque = false
		if shape[b] != 0:
			has_special = true


## Обновление флагов при записи одного блока (консервативно).
func note_block(block: int, opaque: PackedByteArray, shape: PackedByteArray) -> void:
	if opaque[block] != 1:
		all_opaque = false
	if shape[block] != 0:
		has_special = true


## Разворачивает однородную секцию в массив без копирования ссылок —
## только для генератора, пока секцию никто не видел.
func ensure_array() -> PackedInt32Array:
	if blocks.is_empty():
		var arr := PackedInt32Array()
		arr.resize(WorldConst.SECTION_VOLUME)
		arr.fill(uniform)
		blocks = arr
	return blocks


func is_uniform() -> bool:
	return blocks.is_empty()


func is_empty() -> bool:
	return blocks.is_empty() and uniform == 0


func get_block(index: int) -> int:
	return uniform if blocks.is_empty() else blocks[index]


func set_block(index: int, block: int) -> void:
	if blocks.is_empty():
		if block == uniform:
			return
		var arr := PackedInt32Array()
		arr.resize(WorldConst.SECTION_VOLUME)
		arr.fill(uniform)
		blocks = arr
	else:
		if blocks[index] == block:
			return
		blocks = blocks.duplicate()
	blocks[index] = block
	version += 1


## Сворачивает массив обратно в одно число, если все блоки совпали.
func try_compact() -> bool:
	if blocks.is_empty():
		return true
	var first := blocks[0]
	for b in blocks:
		if b != first:
			return false
	uniform = first
	blocks = PackedInt32Array()
	return true
