class_name RegionStore
extends RefCounted
## Хранилище изменённых колонн в region-файлах (раздел 2.1 и 21 ТЗ).
##
## Region — 32×32 колонны, файл `r.<rx>.<rz>.kbr`:
##   u32 магия "KBRG", u16 формат, u16 резерв,
##   1024 × (u32 смещение, u32 размер) — таблица колонн (0 — колонны нет),
##   далее блобы колонн.
## Блоб колонны: u32 исходный размер + данные, сжатые zstd. Внутри — палитра строковых ID блоков
## и секции (однородная — один индекс палитры, иначе 4096 × u16). Числовые ID на диск не попадают,
## поэтому порядок блоков в data/ можно менять.
##
## Пишутся только колонны, которые игрок менял (их передаёт ChunkManager). Остальное мир
## генерирует заново по сиду. Потокобезопасен: load_column() вызывается из потоков генерации.

const REGION_MAGIC := 0x4752424B  # "KBRG"
const COLUMN_MAGIC := 0x4343424B  # "KBCC"
const FORMAT := 1
const COLUMNS_PER_REGION := WorldConst.REGION_SIZE * WorldConst.REGION_SIZE
const HEADER_SIZE := 8 + COLUMNS_PER_REGION * 8
const KIND_UNIFORM := 0
const KIND_FULL := 1

## Каталог region-файлов; пустая строка — хранилище только в памяти (временный мир).
var dir: String
var warnings: PackedStringArray = []

var _registry: ContentRegistry
var _mutex := Mutex.new()
var _regions := {}  # Vector2i -> { int индекс -> PackedByteArray блоб }
var _dirty := {}    # Vector2i -> true


func _init(p_dir: String, registry: ContentRegistry) -> void:
	dir = p_dir
	_registry = registry


static func region_of(cpos: Vector2i) -> Vector2i:
	return Vector2i(cpos.x >> 5, cpos.y >> 5)


static func index_in_region(cpos: Vector2i) -> int:
	return (cpos.x & 31) | ((cpos.y & 31) << 5)


func region_path(rpos: Vector2i) -> String:
	return dir.path_join("r.%d.%d.kbr" % [rpos.x, rpos.y])


func has_column(cpos: Vector2i) -> bool:
	_mutex.lock()
	var region := _region(region_of(cpos))
	var ok := region.has(index_in_region(cpos))
	_mutex.unlock()
	return ok


## Сохранённая колонна или null, если её не меняли.
func load_column(cpos: Vector2i) -> ChunkColumn:
	_mutex.lock()
	var blob: PackedByteArray = _region(region_of(cpos)).get(index_in_region(cpos), PackedByteArray())
	_mutex.unlock()
	if blob.is_empty():
		return null
	return decode_column(blob, cpos)


## Кладёт колонну в память; на диск — при flush().
func store_column(col: ChunkColumn) -> void:
	var blob := encode_column(col)
	var rpos := region_of(col.cpos)
	_mutex.lock()
	_region(rpos)[index_in_region(col.cpos)] = blob
	_dirty[rpos] = true
	_mutex.unlock()


## Записывает изменённые region-файлы. Запись атомарная: временный файл, затем замена.
func flush() -> Error:
	if dir.is_empty():
		return OK
	DirAccess.make_dir_recursive_absolute(dir)
	_mutex.lock()
	var to_write := _dirty.keys()
	var snapshot := {}
	for rpos: Vector2i in to_write:
		snapshot[rpos] = _regions[rpos].duplicate()
	_dirty.clear()
	_mutex.unlock()
	var result := OK
	for rpos: Vector2i in to_write:
		var err := _write_region(rpos, snapshot[rpos])
		if err != OK:
			result = err
			_mutex.lock()
			_dirty[rpos] = true
			_mutex.unlock()
	return result


## Сколько колонн сохранено (с учётом файлов на диске, ещё не читанных).
func saved_column_count() -> int:
	_mutex.lock()
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			var parts := f.split(".")
			if parts.size() == 4 and parts[0] == "r" and parts[3] == "kbr":
				_region(Vector2i(parts[1].to_int(), parts[2].to_int()))
	var n := 0
	for r: Dictionary in _regions.values():
		n += r.size()
	_mutex.unlock()
	return n


func encode_column(col: ChunkColumn) -> PackedByteArray:
	var palette := {}  # числовой ID -> индекс палитры
	var ids := PackedStringArray()
	for s in col.sections:
		if s == null:
			continue
		if s.is_uniform():
			_palette_add(palette, ids, s.uniform)
		else:
			for b in s.blocks:
				if not palette.has(b):
					_palette_add(palette, ids, b)

	var buf := StreamPeerBuffer.new()
	buf.put_u32(COLUMN_MAGIC)
	buf.put_u16(FORMAT)
	buf.put_32(col.cpos.x)
	buf.put_32(col.cpos.y)
	buf.put_u16(ids.size())
	for id in ids:
		var bytes := id.to_utf8_buffer()
		buf.put_u16(bytes.size())
		buf.put_data(bytes)
	var count := 0
	for s in col.sections:
		if s != null:
			count += 1
	buf.put_u8(count)
	for si in col.sections.size():
		var s := col.sections[si]
		if s == null:
			continue
		buf.put_u8(si)
		if s.is_uniform():
			buf.put_u8(KIND_UNIFORM)
			buf.put_u16(palette[s.uniform])
		else:
			buf.put_u8(KIND_FULL)
			var data := PackedByteArray()
			data.resize(WorldConst.SECTION_VOLUME * 2)
			for i in WorldConst.SECTION_VOLUME:
				data.encode_u16(i * 2, palette[s.blocks[i]])
			buf.put_data(data)
	var raw := buf.data_array
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


func decode_column(blob: PackedByteArray, expected: Vector2i) -> ChunkColumn:
	var raw := blob.slice(4).decompress(blob.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
	var buf := StreamPeerBuffer.new()
	buf.data_array = raw
	if buf.get_u32() != COLUMN_MAGIC or buf.get_u16() != FORMAT:
		warnings.append("колонна %s: неизвестный формат, будет сгенерирована заново" % expected)
		return null
	var cpos := Vector2i(buf.get_32(), buf.get_32())
	if cpos != expected:
		warnings.append("колонна %s: в файле записана %s" % [expected, cpos])
		return null
	var nums := PackedInt32Array()
	for i in buf.get_u16():
		var bytes: PackedByteArray = buf.get_data(buf.get_u16())[1]
		var id := bytes.get_string_from_utf8()
		var n := _registry.block_num(StringName(id))
		if n < 0:
			warnings.append("колонна %s: блок '%s' больше не существует, заменён воздухом" % [cpos, id])
			n = 0
		nums.append(n)
	var col := ChunkColumn.new(cpos)
	col.from_save = true
	for i in buf.get_u8():
		var si := buf.get_u8()
		var kind := buf.get_u8()
		var s := ChunkSection.new()
		if kind == KIND_UNIFORM:
			s.uniform = nums[buf.get_u16()]
		else:
			var data: PackedByteArray = buf.get_data(WorldConst.SECTION_VOLUME * 2)[1]
			var arr := PackedInt32Array()
			arr.resize(WorldConst.SECTION_VOLUME)
			for j in WorldConst.SECTION_VOLUME:
				arr[j] = nums[data.decode_u16(j * 2)]
			s.blocks = arr
			s.try_compact()
		if not s.is_empty():
			col.sections[si] = s
	return col


func _palette_add(palette: Dictionary, ids: PackedStringArray, num: int) -> void:
	if palette.has(num):
		return
	palette[num] = ids.size()
	ids.append(String(_registry.block_by_num(num).id))


## Region из кэша; при первом обращении читается с диска. Вызывать под мьютексом.
func _region(rpos: Vector2i) -> Dictionary:
	if _regions.has(rpos):
		return _regions[rpos]
	var region := {}
	_regions[rpos] = region
	if dir.is_empty():
		return region
	var path := region_path(rpos)
	if not FileAccess.file_exists(path):
		return region
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < HEADER_SIZE or bytes.decode_u32(0) != REGION_MAGIC or bytes.decode_u16(4) != FORMAT:
		warnings.append("%s: повреждённый или чужой region-файл, пропущен" % path)
		return region
	for i in COLUMNS_PER_REGION:
		var off := bytes.decode_u32(8 + i * 8)
		var size := bytes.decode_u32(12 + i * 8)
		if size == 0:
			continue
		if off + size > bytes.size():
			warnings.append("%s: колонна %d обрезана, пропущена" % [path, i])
			continue
		region[i] = bytes.slice(off, off + size)
	return region


func _write_region(rpos: Vector2i, region: Dictionary) -> Error:
	var header := PackedByteArray()
	header.resize(HEADER_SIZE)
	header.encode_u32(0, REGION_MAGIC)
	header.encode_u16(4, FORMAT)
	var body := PackedByteArray()
	var indices := region.keys()
	indices.sort()
	for i: int in indices:
		var blob: PackedByteArray = region[i]
		header.encode_u32(8 + i * 8, HEADER_SIZE + body.size())
		header.encode_u32(12 + i * 8, blob.size())
		body.append_array(blob)
	var path := region_path(rpos)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(header)
	f.store_buffer(body)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)
