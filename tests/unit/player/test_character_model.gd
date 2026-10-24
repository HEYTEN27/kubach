extends GutTest
## Модель персонажа: данные редактора, построение, экипировка на модели.


func test_character_data() -> void:
	assert_gte(Registry.get_entries("hairstyles").size(), 15, "причёсок 15+ (раздел 4.2)")
	assert_gt(Registry.get_entries("beards").size(), 3)
	assert_gt(Registry.get_entries("face_presets").size(), 3)
	for part in ["eyes", "brows", "nose", "mouth", "scar"]:
		var n := 0
		for e in Registry.get_entries("face_parts"):
			if String(e["part"]) == part:
				n += 1
		assert_gt(n, 1, part)


func test_builds_every_hairstyle_and_beard() -> void:
	var m := CharacterModel.new()
	add_child_autofree(m)
	m.setup(Registry)
	for e in Registry.get_entries("hairstyles"):
		var a := CharacterModel.default_appearance()
		a["hair"] = e["id"]
		m.set_appearance(a)
	for e in Registry.get_entries("beards"):
		var a := CharacterModel.default_appearance()
		a["beard"] = e["id"]
		m.set_appearance(a)
	assert_gt(m.get_child_count(), 0)


func test_random_appearance_is_valid() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 10:
		var a := CharacterModel.random_appearance(Registry, rng)
		assert_true(Registry.has_entry("hairstyles", StringName(a["hair"])))
		assert_true(Registry.has_entry("face_parts", StringName(a["eyes"])))
		assert_between(float(a["height"]), 0.9, 1.1)


func test_equipment_changes_model() -> void:
	var m := CharacterModel.new()
	add_child_autofree(m)
	m.setup(Registry)
	var before := _mesh_count(m)
	var equip := Inventory.new(Registry, PlayerInventory.EQUIP_KINDS.size())
	equip.slot_kinds = PlayerInventory.EQUIP_KINDS.duplicate()
	equip.set_stack(0, ItemStack.create(Registry.item(&"fur_hat")))
	equip.set_stack(5, ItemStack.create(Registry.item(&"large_backpack")))
	equip.set_stack(1, ItemStack.create(Registry.item(&"fur_coat")))
	m.set_equipment(equip)
	assert_gt(_mesh_count(m), before, "шапка, тулуп и рюкзак видны на модели")


func _mesh_count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _mesh_count(ch)
	return c
