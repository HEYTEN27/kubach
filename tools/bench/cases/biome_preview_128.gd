extends RefCounted
## Предпросмотр карты биомов 128×128 в одном потоке (экран создания мира считает 512×512 в пуле).

var name := "biome_preview_128"
var iterations := 3
var _preview: BiomePreview


func setup() -> void:
	var reg := Engine.get_main_loop().root.get_node("/root/Registry") as ContentRegistry
	_preview = BiomePreview.new(TerrainGenerator.new(4242, reg))


func run() -> void:
	_preview.render_now(128)


func teardown() -> void:
	pass
