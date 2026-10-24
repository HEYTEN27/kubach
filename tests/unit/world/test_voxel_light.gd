extends GutTest
## Воксельное освещение: правила распространения (эталон на GDScript) и совпадение с C++.

const OPAQUE := VoxelLight.OPAQUE

var gd: VoxelLight
var native: Object
var stone: int
var lava: int
var leaves: int


func before_all() -> void:
	gd = VoxelLight.new(Registry)
	if ClassDB.class_exists(&"NativeLight"):
		native = VoxelLight.create_best(Registry)
	stone = Registry.block_num(&"granite")
	lava = Registry.block_num(&"lava")
	leaves = Registry.block_num(&"oak_leaves")


func _box(sx: int, sy: int, sz: int, fill: int = 0) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(sx * sy * sz)
	a.fill(fill)
	return a


func test_native_light_loaded() -> void:
	assert_true(VoxelLight.is_native(native), "native/bin: NativeLight загружен")


func test_open_sky_is_full() -> void:
	var sky := VoxelLight.propagate_sky(_box(4, 8, 4), 4, 8, 4)
	for v in sky:
		assert_eq(v, 15)


func test_sky_under_roof_decays_sideways() -> void:
	# Крыша над x = 0…3, открыто только x = 4…7: под крышей свет падает на 1 за блок вбок.
	var sx := 8
	var sy := 4
	var sz := 1
	var att := _box(sx, sy, sz)
	for x in 4:
		att[x + 3 * sx * sz] = OPAQUE
	var sky := VoxelLight.propagate_sky(att, sx, sy, sz)
	assert_eq(sky[4 + 0], 15, "под открытым небом — 15")
	assert_eq(sky[3 + 0], 14)
	assert_eq(sky[0 + 0], 11)
	assert_eq(sky[0 + 3 * sx], 0, "в самой крыше света нет")


func test_leaves_filter_sky() -> void:
	var att := _box(1, 6, 1)
	att[5] = 1
	att[4] = 1
	var sky := VoxelLight.propagate_sky(att, 1, 6, 1)
	assert_eq(sky[3], 13, "два слоя листвы — минус 2")


func test_block_light_spreads_and_stops_at_walls() -> void:
	var sx := 20
	var att := _box(sx, 1, 1)
	var emit := PackedByteArray()
	emit.resize(sx * 3)
	emit[0] = 15
	emit[1] = 9
	att[17] = OPAQUE
	var r := VoxelLight.propagate_block(att, emit, 0, sx, 1, 1)
	var g := VoxelLight.propagate_block(att, emit, 1, sx, 1, 1)
	assert_eq(r[0], 15)
	assert_eq(r[5], 10)
	assert_eq(g[5], 4, "зелёный канал слабее — цвет света сохраняется")
	assert_eq(r[16], 0, "дальше 15 блоков не доходит")
	assert_eq(r[18], 0, "за стеной темно")


func test_native_propagation_matches_reference() -> void:
	if native == null:
		fail_test("нет нативной библиотеки")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var sx := 21
	var sy := 17
	var sz := 13
	var att := _box(sx, sy, sz)
	var emit := PackedByteArray()
	emit.resize(att.size() * 3)
	for i in att.size():
		var k := rng.randi() % 10
		att[i] = OPAQUE if k < 3 else (rng.randi() % 3 if k < 5 else 0)
		if rng.randi() % 200 == 0:
			emit[i * 3] = 15
			emit[i * 3 + 2] = 7
	assert_eq(native.propagate_sky(att, sx, sy, sz), VoxelLight.propagate_sky(att, sx, sy, sz), "небо")
	for ch in 3:
		assert_eq(native.propagate_block(att, emit, ch, sx, sy, sz), VoxelLight.propagate_block(att, emit, ch, sx, sy, sz), "канал %d" % ch)


## Мир-коробка: 9 колонн, секции 20…22 — каменный пол, пещера с лавой, крыша.
func _cave_world() -> Array:
	var cols := []
	for ci in 9:
		var col := []
		col.resize(WorldConst.SECTIONS_PER_COLUMN)
		var floor_s := ChunkSection.filled(stone)
		var mid := ChunkSection.new()
		for ly in 16:
			for lz in 16:
				for lx in 16:
					var wall := ly >= 12 or ly < 2
					mid.set_block(WorldConst.local_index(lx, ly, lz), stone if wall else 0)
		if ci == 4:
			mid.set_block(WorldConst.local_index(8, 2, 8), lava)
			# Окно в крыше над (2, *, 2).
			for ly in range(12, 16):
				mid.set_block(WorldConst.local_index(2, ly, 2), 0)
		col[20] = GreedyMesher.snapshot(floor_s)
		col[21] = GreedyMesher.snapshot(mid)
		cols.append(col)
	return cols


func test_light_column_cave() -> void:
	var res := gd.light_column(_cave_world())
	assert_eq(res.size(), WorldConst.SECTIONS_PER_COLUMN)
	assert_eq(res[30], VoxelLight.SKY_FULL, "выше всего — полный свет неба")
	assert_eq(res[5], VoxelLight.DARK, "ниже области — темно")
	assert_true(res[21] is PackedByteArray, "секция с пещерой — неоднородный свет")
	var data: PackedByteArray = res[21]
	# Клетка (8, 3, 8) над лавой: в данных секции с полями индекс (x+1) + (z+1)*18 + (y+1)*324.
	var i := ((8 + 1) + (8 + 1) * 18 + (3 + 1) * 324) * 4
	assert_eq(data[i + 1], 14 * 17, "над лавой красный канал 14")
	# Под окном в крыше светит небо, вдали от окна — нет.
	var w := ((2 + 1) + (2 + 1) * 18 + (6 + 1) * 324) * 4
	assert_eq(data[w], 15 * 17, "небо через окно падает вниз без потерь")


func test_native_light_column_matches_reference() -> void:
	if native == null:
		fail_test("нет нативной библиотеки")
		return
	var world := _cave_world()
	var a := gd.light_column(world)
	var b: Array = native.light_column(world)
	for si in a.size():
		assert_eq(typeof(b[si]), typeof(a[si]), "секция %d: тип" % si)
		assert_eq(b[si], a[si], "секция %d" % si)


func test_texture_from_light_data() -> void:
	var res := gd.light_column(_cave_world())
	var tex := VoxelLight.make_texture(res[21])
	assert_eq(tex.get_width(), 18)
	assert_eq(tex.get_depth(), 18)
