class_name PlayerInventory
extends RefCounted
## Инвентарь игрока (раздел 4.4 ТЗ): хотбар 9, основной 27, рюкзак (+9/+18/+27 — по надетому
## рюкзаку; содержимое живёт в данных самого рюкзака и уходит вместе с ним) и 9 слотов
## экипировки: голова, тело, ноги, ступни, руки, спина, 2 аксессуара, вторая рука.

signal changed()
signal selected_changed(index: int)
signal equipment_changed()

const HOTBAR := 9
const MAIN := 27
const EQUIP_KINDS: Array[StringName] = [&"head", &"body", &"legs", &"feet", &"hands", &"back", &"accessory",
	&"accessory", &"offhand"]
const BACK_SLOT := 5
const OFFHAND_SLOT := 8
## Сколько можно нести без перегруза, кг (вес — опция в настройках).
const CARRY_LIMIT := 40.0

var registry: ContentRegistry
var hotbar: Inventory
var main: Inventory
var backpack: Inventory
var equipment: Inventory
var selected := 0

var _backpack_item: ItemStack


func _init(p_registry: ContentRegistry) -> void:
	registry = p_registry
	hotbar = Inventory.new(registry, HOTBAR, "hotbar")
	main = Inventory.new(registry, MAIN, "main")
	backpack = Inventory.new(registry, 0, "backpack")
	backpack.deny_kinds = [&"backpack"]
	equipment = Inventory.new(registry, EQUIP_KINDS.size(), "equipment")
	equipment.slot_kinds = EQUIP_KINDS.duplicate()
	# Методы, а не лямбды: лямбда держит self, и пара объектов не освободится (цикл RefCounted).
	for inv: Inventory in [hotbar, main, backpack]:
		inv.changed.connect(_on_storage_changed)
	equipment.changed.connect(_on_equipment_changed)


## Хранилища, куда кладутся подобранные предметы, по порядку.
func storages() -> Array[Inventory]:
	return [hotbar, main, backpack]


func held() -> ItemStack:
	return hotbar.get_stack(selected)


func held_def() -> ItemDef:
	var s := held()
	return registry.item(s.id) if s != null else null


func offhand() -> ItemStack:
	return equipment.get_stack(OFFHAND_SLOT)


func select(i: int) -> void:
	selected = posmod(i, HOTBAR)
	selected_changed.emit(selected)


## Подобрать стопку: возвращает остаток (не поместилось).
func add(s: ItemStack) -> int:
	for inv: Inventory in storages():
		if s.count == 0:
			break
		inv.add(s)
	return s.count


func count_of(id: StringName) -> int:
	var n := 0
	for inv: Inventory in storages():
		n += inv.count_of(id)
	return n


## Израсходовать один предмет из руки (поставить блок, съесть).
func consume_held(n: int = 1) -> void:
	var s := held()
	if s == null:
		return
	s.count -= n
	hotbar.set_stack(selected, s if s.count > 0 else null)


## Износ предмета в руке. Сломался — исчезает; возвращает true, если сломался.
func damage_held(amount: int = 1) -> bool:
	var s := held()
	if s == null or not s.data.has("durability"):
		return false
	s.data["durability"] = int(s.data["durability"]) - amount
	if int(s.data["durability"]) <= 0:
		hotbar.set_stack(selected, null)
		return true
	hotbar.changed.emit()
	return false


func total_weight() -> float:
	return hotbar.total_weight() + main.total_weight() + backpack.total_weight() + equipment.total_weight()


## Множитель скорости от перегруза: до лимита 1, затем линейно до 0,4 при двойном весе.
func overload_factor() -> float:
	var w := total_weight()
	if w <= CARRY_LIMIT:
		return 1.0
	return clampf(1.0 - 0.6 * (w - CARRY_LIMIT) / CARRY_LIMIT, 0.4, 1.0)


func armor_total() -> float:
	var a := 0.0
	for s: ItemStack in equipment.slots:
		if s != null:
			var d := registry.item(s.id)
			if d != null:
				a += d.armor
	return a


func insulation_total() -> float:
	var t := 0.0
	for s: ItemStack in equipment.slots:
		if s != null:
			var d := registry.item(s.id)
			if d != null:
				t += d.insulation
	return t


## Свет предмета во второй руке (факел) или в основной: [уровень 0…15, цвет].
func hand_light() -> Array:
	var best := [0, Color.WHITE]
	for s: ItemStack in [offhand(), held()]:
		if s == null:
			continue
		var d := registry.item(s.id)
		if d != null and d.light > best[0]:
			best = [d.light, d.light_color]
	return best


## Рюкзак надет/снят: содержимое уходит в данные старого рюкзака и берётся из нового.
func sync_backpack() -> void:
	var cur := equipment.get_stack(BACK_SLOT)
	if cur == _backpack_item:
		return
	if _backpack_item != null:
		_backpack_item.data["contents"] = backpack.to_array()
		if backpack.is_empty():
			_backpack_item.data.erase("contents")
	_backpack_item = cur
	var d := registry.item(cur.id) if cur != null else null
	var n := d.backpack_slots if d != null else 0
	backpack.slots.resize(n)
	var contents: Variant = cur.data.get("contents", []) if cur != null else []
	backpack.from_array(contents if contents is Array else [])
	if cur != null:
		cur.data.erase("contents")


func _on_storage_changed() -> void:
	changed.emit()


func _on_equipment_changed() -> void:
	sync_backpack()
	equipment_changed.emit()
	changed.emit()


func to_dict() -> Dictionary:
	# Содержимое рюкзака сохраняется в данных надетого рюкзака.
	var eq := equipment.to_array()
	if _backpack_item != null and not backpack.is_empty():
		var d: Dictionary = eq[BACK_SLOT]
		var data: Dictionary = d.get("data", {}).duplicate()
		data["contents"] = backpack.to_array()
		d["data"] = data
	return { "hotbar": hotbar.to_array(), "main": main.to_array(), "equipment": eq, "selected": selected }


func from_dict(d: Dictionary) -> void:
	_backpack_item = null
	backpack.slots.resize(0)
	hotbar.from_array(d.get("hotbar", []))
	main.from_array(d.get("main", []))
	equipment.from_array(d.get("equipment", []))
	sync_backpack()
	selected = clampi(int(d.get("selected", 0)), 0, HOTBAR - 1)
