class_name BiomePreview
extends RefCounted
## Предпросмотр карты биомов для экрана создания мира (раздел 2.2): цвет биома с отмывкой
## рельефа. Считается построчно в WorkerThreadPool, уровнями детализации 64 → 128 → 256 → 512.

signal level_ready(image: Image, size: int)
signal finished

const LEVELS: Array[int] = [64, 128, 256, 512]

## Сколько блоков мира в стороне карты.
var span := 8192
var center := Vector2i.ZERO

var _gen: TerrainGenerator
var _size := 0
var _rows := {}
var _mutex := Mutex.new()
var _task := -1
var _level := 0
var _cancelled := false


func _init(gen: TerrainGenerator) -> void:
	_gen = gen


## Запускает расчёт. Вызывать poll() каждый кадр из главного потока.
func start() -> void:
	_level = 0
	_start_level()


func cancel() -> void:
	_cancelled = true
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1


func is_running() -> bool:
	return _task >= 0


func poll() -> void:
	if _task < 0 or not WorkerThreadPool.is_group_task_completed(_task):
		return
	WorkerThreadPool.wait_for_group_task_completion(_task)
	_task = -1
	if _cancelled:
		return
	var data := PackedByteArray()
	for y in _size:
		data.append_array(_rows[y])
	var img := Image.create_from_data(_size, _size, false, Image.FORMAT_RGB8, data)
	level_ready.emit(img, _size)
	_level += 1
	if _level < LEVELS.size():
		_start_level()
	else:
		finished.emit()


## Синхронно — для тестов.
func render_now(size: int) -> Image:
	_size = size
	_rows.clear()
	for y in size:
		_row(y)
	var data := PackedByteArray()
	for y in size:
		data.append_array(_rows[y])
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, data)


func _start_level() -> void:
	_size = LEVELS[_level]
	_rows.clear()
	_task = WorkerThreadPool.add_group_task(_row, _size, -1, false, "biome preview")


func _row(y: int) -> void:
	var row := PackedByteArray()
	row.resize(_size * 3)
	var step := float(span) / _size
	var sea := float(_gen.sea_level)
	var z := center.y - span / 2 + int((y + 0.5) * step)
	for x in _size:
		if _cancelled:
			return
		var wx := center.x - span / 2 + int((x + 0.5) * step)
		var s := _gen.preview_sample(wx, z)
		var c: Color = _gen.biomes.map_color[int(s.x)]
		var h := s.y
		if h < sea:
			c = c.darkened(clampf((sea - h) / 60.0, 0.0, 0.55))
		else:
			c = c.lightened(clampf((h - sea) / 220.0, 0.0, 0.35))
		# Граница мира — красная линия.
		if absi(wx) >= WorldConst.WORLD_HALF or absi(z) >= WorldConst.WORLD_HALF:
			c = Color(0.6, 0.1, 0.1)
		row[x * 3] = c.r8
		row[x * 3 + 1] = c.g8
		row[x * 3 + 2] = c.b8
	_mutex.lock()
	_rows[y] = row
	_mutex.unlock()
