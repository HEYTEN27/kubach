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


static func filled(block: int) -> ChunkSection:
	var s := ChunkSection.new()
	s.uniform = block
	return s


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
