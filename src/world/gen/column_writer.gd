class_name ColumnWriter
extends RefCounted
## Запись блоков в колонну во время генерации (мировые координаты, отсечение по колонне).
## Генератор пишет в свежие секции, которые ещё никто не видел, поэтому без копирования массивов.

var col: ChunkColumn
var x0: int
var z0: int
## Блоки, которые «мягкая» запись может заменить (воздух, растения, слои): 1 — можно.
var soft_replaceable: PackedByteArray
## Блоки, которые может заменить ствол дерева (всё непрочное + листва).
var log_replaceable: PackedByteArray
var _opaque: PackedByteArray
var _shape: PackedByteArray


func _init(p_col: ChunkColumn, registry: ContentRegistry) -> void:
	col = p_col
	x0 = col.cpos.x * 16
	z0 = col.cpos.y * 16
	_opaque = registry.block_opaque
	_shape = registry.block_shape
	soft_replaceable = PackedByteArray()
	log_replaceable = PackedByteArray()
	for n in registry.block_count():
		var shape := registry.block_shape[n]
		var soft := n == 0 or shape != BlockDef.SHAPE_CUBE
		soft_replaceable.append(1 if soft else 0)
		var leaf := registry.block_render[n] == BlockDef.RENDER_CUTOUT
		var fluid := registry.block_render[n] == BlockDef.RENDER_LIQUID
		log_replaceable.append(1 if soft or leaf or fluid else 0)


func inside(x: int, z: int) -> bool:
	return x >= x0 and x < x0 + 16 and z >= z0 and z < z0 + 16


## Блок в мировых координатах; вне колонны — −1.
func get_block(x: int, y: int, z: int) -> int:
	var lx := x - x0
	var lz := z - z0
	if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y < WorldConst.MIN_Y or y >= WorldConst.MAX_Y:
		return -1
	var s := col.sections[(y - WorldConst.MIN_Y) >> 4]
	if s == null:
		return 0
	if s.blocks.is_empty():
		return s.uniform
	return s.blocks[lx | (lz << 4) | ((y & 15) << 8)]


func set_block(x: int, y: int, z: int, block: int) -> void:
	var lx := x - x0
	var lz := z - z0
	if lx < 0 or lx > 15 or lz < 0 or lz > 15 or y < WorldConst.MIN_Y or y >= WorldConst.MAX_Y:
		return
	var si := (y - WorldConst.MIN_Y) >> 4
	var s := col.sections[si]
	if s == null:
		if block == 0:
			return
		s = ChunkSection.new()
		col.sections[si] = s
	if s.blocks.is_empty():
		if s.uniform == block:
			return
		s.ensure_array()
	s.blocks[lx | (lz << 4) | ((y & 15) << 8)] = block
	if _opaque[block] != 1:
		s.all_opaque = false
	if _shape[block] != 0:
		s.has_special = true


## Запись только поверх воздуха/растений (листва, снег).
func place_soft(x: int, y: int, z: int, block: int) -> void:
	var cur := get_block(x, y, z)
	if cur >= 0 and soft_replaceable[cur] == 1:
		set_block(x, y, z, block)


## Запись ствола: поверх непрочного, листвы и воды.
func place_log(x: int, y: int, z: int, block: int) -> void:
	var cur := get_block(x, y, z)
	if cur >= 0 and log_replaceable[cur] == 1:
		set_block(x, y, z, block)
