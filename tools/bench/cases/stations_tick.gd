extends RefCounted
## Тик 40 станций (главный поток, раз в 0,25 с): 20 печей с жаром и плавкой, 20 дробилок.
## Плюс ModelMesher секции с 16 станциями (в потоке мешинга).

var name := "stations_tick"
var iterations := 20
var _stations: Array[Station] = []
var _mm: ModelMesher
var _center: Array


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	var data := CraftingData.shared(reg)
	for i in 20:
		var f := Station.new(data, &"furnace")
		f.fuel.set_stack(0, ItemStack.make(&"coal", 64))
		f.inputs.set_stack(0, ItemStack.make(&"tin_concentrate", 64))
		_stations.append(f)
		var c := Station.new(data, &"crusher")
		c.inputs.set_stack(0, ItemStack.make(&"malachite_ore", 64))
		_stations.append(c)
	_mm = ModelMesher.new(reg)
	var sec := ChunkSection.new()
	var ids := [&"workbench", &"stone_furnace", &"bloomery", &"iron_anvil"]
	for i in 16:
		sec.set_block(WorldConst.local_index((i % 4) * 4, 2, (i / 4) * 4), reg.block_num(ids[i % 4]))
	_center = GreedyMesher.snapshot(sec)


func run() -> void:
	for s in _stations:
		s.advance(0.25)
	_mm.build(_center, {})


func teardown() -> void:
	_stations.clear()
