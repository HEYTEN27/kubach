class_name WorldConst
extends RefCounted
## Размеры мира и перевод координат (раздел 2.1 ТЗ).
##
## Мировые координаты блоков — целые; блок (x, y, z) занимает куб [x, x+1) × [y, y+1) × [z, z+1).
## Колонна чанка — 16×16 по X/Z на всю высоту; секция — 16×16×16 внутри колонны.

const SECTION_SIZE := 16
const SECTION_VOLUME := 4096
const MIN_Y := -256
## Верхняя граница (исключительно): блоки занимают Y от −256 до 319 включительно.
const MAX_Y := 320
const HEIGHT := MAX_Y - MIN_Y
const SECTIONS_PER_COLUMN := HEIGHT / SECTION_SIZE
## Мир — X и Z в [−WORLD_HALF, WORLD_HALF).
const WORLD_HALF := 15000
## Region-файл — REGION_SIZE × REGION_SIZE колонн.
const REGION_SIZE := 32


## Деление с округлением вниз (для отрицательных координат `/` в GDScript округляет к нулю).
static func floor_div(a: int, b: int) -> int:
	return floori(float(a) / float(b))


static func floor_mod(a: int, b: int) -> int:
	return a - floor_div(a, b) * b


## Колонна, которой принадлежит блок.
static func block_to_column(x: int, z: int) -> Vector2i:
	return Vector2i(x >> 4, z >> 4)


## Индекс секции внутри колонны (0…35) или −1 вне высотного диапазона.
static func section_index(y: int) -> int:
	if y < MIN_Y or y >= MAX_Y:
		return -1
	return (y - MIN_Y) >> 4


## Нижняя мировая Y секции.
static func section_base_y(index: int) -> int:
	return MIN_Y + index * SECTION_SIZE


## Индекс блока внутри секции. Порядок: X быстрее всего, затем Z, затем Y.
static func local_index(lx: int, ly: int, lz: int) -> int:
	return lx | (lz << 4) | (ly << 8)


static func is_inside_world_xz(x: int, z: int) -> bool:
	return x >= -WORLD_HALF and x < WORLD_HALF and z >= -WORLD_HALF and z < WORLD_HALF
