class_name ItemStack
extends RefCounted
## Стопка предметов: id, количество и данные экземпляра (прочность, качество, свежесть, цвет,
## содержимое рюкзака). Стопки складываются, только если у них одинаковые id и данные — так еда
## разной свежести или качества не смешивается (раздел 4.4 ТЗ).

var id: StringName
var count := 1
## Данные экземпляра: "durability" (int), "quality" (float), "freshness" (float 0…1),
## "color" (строка #rrggbb — для одежды), "contents" (Array — содержимое рюкзака).
var data := {}


static func make(p_id: StringName, p_count: int = 1, p_data: Dictionary = {}) -> ItemStack:
	var s := ItemStack.new()
	s.id = p_id
	s.count = p_count
	s.data = p_data.duplicate(true)
	return s


## Новый экземпляр предмета с начальными данными (полная прочность).
static func create(def: ItemDef, p_count: int = 1) -> ItemStack:
	var s := make(def.id, mini(p_count, def.stack))
	if def.durability > 0:
		s.data["durability"] = def.durability
	if def.is_food() and float(def.food.get("spoil_days", 0.0)) > 0.0:
		s.data["freshness"] = 1.0
	return s


func copy() -> ItemStack:
	return make(id, count, data)


func is_empty() -> bool:
	return count <= 0 or id == &""


## Можно ли положить other поверх этой стопки (без учёта места).
func can_merge(other: ItemStack) -> bool:
	return other != null and other.id == id and data == other.data


## Отделить n штук в новую стопку.
func split(n: int) -> ItemStack:
	n = clampi(n, 0, count)
	var s := make(id, n, data)
	count -= n
	return s


func to_dict() -> Dictionary:
	var d := { "id": String(id), "n": count }
	if not data.is_empty():
		d["data"] = data
	return d


static func from_dict(d: Dictionary) -> ItemStack:
	if not d.has("id"):
		return null
	return make(StringName(d["id"]), int(d.get("n", 1)), d.get("data", {}))
