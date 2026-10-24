class_name ChunkColumn
extends RefCounted
## Колонна чанка: 36 секций по вертикали. Пустые (воздушные) секции — null.

var cpos: Vector2i
var sections: Array[ChunkSection] = []
## Изменена игроком с момента загрузки — при выгрузке или сохранении пишется в region-файл.
var dirty := false
## Колонна пришла из сохранения, а не из генератора.
var from_save := false
## Индекс биома (в BiomeSource) для каждого столба x + z*16.
var biomes := PackedByteArray()
## Цвета биомов с блендингом: сетка 5×5 узлов (через 4 блока) × 8 каналов (сезон*2 + 0 трава, + 1 листва).
## Не сохраняются: пересчитываются генератором по сиду.
var tints := PackedColorArray()
## Минимальная высота поверхности рельефа по колонне (до пещер). Секции целиком ниже неё
## «глубокие»: их мешат только рядом с игроком (отсечение пещер).
var surface_min := WorldConst.MAX_Y


func _init(p_cpos: Vector2i = Vector2i.ZERO) -> void:
	cpos = p_cpos
	sections.resize(WorldConst.SECTIONS_PER_COLUMN)


func get_section(index: int) -> ChunkSection:
	return sections[index]


## Блок по локальным X/Z (0…15) и мировой Y. Вне высоты — воздух.
func get_block(lx: int, y: int, lz: int) -> int:
	var si := WorldConst.section_index(y)
	if si < 0:
		return 0
	var s := sections[si]
	if s == null:
		return 0
	return s.get_block(WorldConst.local_index(lx, y & 15, lz))


func biome_at(lx: int, lz: int) -> int:
	return biomes[lx + lz * 16] if biomes.size() == 256 else -1


func set_block(lx: int, y: int, lz: int, block: int) -> bool:
	var si := WorldConst.section_index(y)
	if si < 0:
		return false
	var s := sections[si]
	if s == null:
		if block == 0:
			return true
		s = ChunkSection.new()
		sections[si] = s
	s.set_block(WorldConst.local_index(lx, y & 15, lz), block)
	if block == 0 and s.try_compact() and s.uniform == 0:
		sections[si] = null
	return true


## Самый верхний непустой блок колонны (мировая Y) или MIN_Y − 1.
func top_block_y(lx: int, lz: int) -> int:
	for si in range(WorldConst.SECTIONS_PER_COLUMN - 1, -1, -1):
		var s := sections[si]
		if s == null:
			continue
		for ly in range(15, -1, -1):
			if s.get_block(WorldConst.local_index(lx, ly, lz)) != 0:
				return WorldConst.section_base_y(si) + ly
	return WorldConst.MIN_Y - 1
