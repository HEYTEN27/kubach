extends GutTest
## Сплавы по пропорциям: бронза 88/12, качество падает с отклонением.

var data: CraftingData
var bronze: Dictionary


func before_all() -> void:
	data = CraftingData.new(Registry)
	for a in data.alloys:
		if String(a["id"]) == "bronze":
			bronze = a


func _mix(cu: int, sn: int) -> Array:
	return [ItemStack.make(&"copper_ingot", cu), ItemStack.make(&"tin_ingot", sn)]


func test_exact_proportion() -> void:
	var a := Alloy.analyze(bronze, _mix(22, 3))
	assert_true(a["valid"])
	assert_eq(int(a["units"]), 25)
	assert_almost_eq(float(a["deviation"]), 0.0, 0.001)
	assert_almost_eq(float(a["factor"]), 1.0, 0.001)


func test_deviation_lowers_factor() -> void:
	var good := Alloy.analyze(bronze, _mix(7, 1))
	var bad := Alloy.analyze(bronze, _mix(1, 1))
	assert_gt(float(good["factor"]), 0.85)
	assert_eq(float(bad["factor"]), 0.0, "50/50 — далеко от бронзы")


func test_invalid_mixes() -> void:
	assert_false(Alloy.analyze(bronze, [ItemStack.make(&"copper_ingot", 5)])["valid"], "нет олова")
	var mix := _mix(7, 1)
	mix.append(ItemStack.make(&"granite", 1))
	assert_false(Alloy.analyze(bronze, mix)["valid"], "посторонний камень")
	assert_eq(String(Alloy.find(data, _mix(7, 1))["id"]), "bronze")
	assert_eq(String(Alloy.find(data, [ItemStack.make(&"iron_ingot", 9), ItemStack.make(&"charcoal", 1)])["id"]), "steel")
	assert_true(Alloy.find(data, [ItemStack.make(&"iron_ingot", 9)]).is_empty())
