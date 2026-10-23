extends RefCounted
## Полная загрузка data/ реестром. Растёт с количеством контента; цель — < 200 мс на старте.

var name := "registry_load"
var iterations := 20
var _reg: ContentRegistry


func setup() -> void:
	_reg = ContentRegistry.new()


func run() -> void:
	_reg.load_all()


func teardown() -> void:
	_reg.free()
