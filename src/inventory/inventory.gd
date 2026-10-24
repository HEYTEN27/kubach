class_name Inventory
extends RefCounted
## Набор ячеек со стопками (раздел 4.4 ТЗ): хотбар, основной инвентарь, рюкзак, экипировка,
## сундук. Ячейка — ItemStack или null. Ячейки могут принимать только предметы своего слота
## экипировки (slot_kinds). Вес и стаки — по определениям из Registry.

signal changed()

var registry: ContentRegistry
var slots: Array = []
## Для экипировки: вид слота на ячейку (head, body, …); пусто — принимает всё.
var slot_kinds: Array[StringName] = []
## Виды предметов, которые сюда класть нельзя (рюкзак в рюкзак).
var deny_kinds: Array[StringName] = []
var name := ""


func _init(p_registry: ContentRegistry, size: int, p_name: String = "") -> void:
	registry = p_registry
	name = p_name
	slots.resize(size)


func size() -> int:
	return slots.size()


func get_stack(i: int) -> ItemStack:
	return slots[i] if i >= 0 and i < slots.size() else null


func set_stack(i: int, s: ItemStack) -> void:
	slots[i] = s if s != null and not s.is_empty() else null
	changed.emit()


func max_stack(id: StringName) -> int:
	var d := registry.item(id)
	return d.stack if d != null else 64


## Подходит ли стопка в ячейку (вид слота экипировки).
func accepts(i: int, s: ItemStack) -> bool:
	if s == null:
		return true
	var d := registry.item(s.id)
	if d == null:
		return false
	if not deny_kinds.is_empty() and deny_kinds.has(d.kind):
		return false
	if slot_kinds.is_empty() or slot_kinds[i] == &"":
		return true
	return d.equip == slot_kinds[i]


## Добавляет стопку: сначала докладывает в подходящие стопки, затем в пустые ячейки.
## Возвращает остаток (0 — всё поместилось). Стопка s уменьшается на положенное.
func add(s: ItemStack) -> int:
	if s == null or s.is_empty():
		return 0
	var limit := max_stack(s.id)
	if not accepts(0, s) and slot_kinds.is_empty():
		return s.count
	for i in slots.size():
		var cur: ItemStack = slots[i]
		if cur != null and cur.can_merge(s) and cur.count < limit:
			var n := mini(limit - cur.count, s.count)
			cur.count += n
			s.count -= n
			if s.count == 0:
				changed.emit()
				return 0
	for i in slots.size():
		if slots[i] == null and accepts(i, s):
			var n := mini(limit, s.count)
			slots[i] = s.split(n)
			if s.count == 0:
				changed.emit()
				return 0
	changed.emit()
	return s.count


## Сколько штук предмета (с любыми данными).
func count_of(id: StringName) -> int:
	var n := 0
	for s: ItemStack in slots:
		if s != null and s.id == id:
			n += s.count
	return n


## Забирает до n штук предмета; возвращает сколько забрано.
func remove(id: StringName, n: int) -> int:
	var taken := 0
	for i in range(slots.size() - 1, -1, -1):
		var s: ItemStack = slots[i]
		if s == null or s.id != id:
			continue
		var k := mini(n - taken, s.count)
		s.count -= k
		taken += k
		if s.count == 0:
			slots[i] = null
		if taken >= n:
			break
	if taken > 0:
		changed.emit()
	return taken


func is_empty() -> bool:
	for s in slots:
		if s != null:
			return false
	return true


func clear() -> void:
	for i in slots.size():
		slots[i] = null
	changed.emit()


## Сколько ещё штук предмета влезет.
func space_for(s: ItemStack) -> int:
	var limit := max_stack(s.id)
	var n := 0
	for i in slots.size():
		var cur: ItemStack = slots[i]
		if cur == null:
			if accepts(i, s):
				n += limit
		elif cur.can_merge(s):
			n += maxi(0, limit - cur.count)
	return n


## Сортировка: сливает одинаковые стопки и упорядочивает по виду и названию.
func sort() -> void:
	var all: Array[ItemStack] = []
	for s: ItemStack in slots:
		if s != null:
			all.append(s)
	var merged: Array[ItemStack] = []
	for s in all:
		var limit := max_stack(s.id)
		for m in merged:
			if m.can_merge(s) and m.count < limit:
				var n := mini(limit - m.count, s.count)
				m.count += n
				s.count -= n
				if s.count == 0:
					break
		if s.count > 0:
			merged.append(s)
	var reg := registry
	merged.sort_custom(func(a: ItemStack, b: ItemStack) -> bool:
		var da := reg.item(a.id)
		var db := reg.item(b.id)
		var ka := String(da.kind) if da else ""
		var kb := String(db.kind) if db else ""
		if ka != kb:
			return ka < kb
		var na := da.display_name() if da else String(a.id)
		var nb := db.display_name() if db else String(b.id)
		if na != nb:
			return na < nb
		return a.count > b.count)
	for i in slots.size():
		slots[i] = merged[i] if i < merged.size() else null
	changed.emit()


func total_weight() -> float:
	var w := 0.0
	for s: ItemStack in slots:
		if s == null:
			continue
		var d := registry.item(s.id)
		if d != null:
			w += d.weight * s.count
		var contents: Variant = s.data.get("contents")
		if contents is Array:
			for c: Variant in contents:
				if c is Dictionary:
					var cd := registry.item(StringName(c.get("id", "")))
					if cd != null:
						w += cd.weight * int(c.get("n", 1))
	return w


func to_array() -> Array:
	var out := []
	for s: ItemStack in slots:
		out.append(s.to_dict() if s != null else null)
	return out


## Загружает ячейки; неизвестные предметы (удалённые из data/) пропускаются с предупреждением.
func from_array(arr: Array) -> void:
	for i in slots.size():
		slots[i] = null
	for i in mini(arr.size(), slots.size()):
		var d: Variant = arr[i]
		if d is Dictionary:
			var s := ItemStack.from_dict(d)
			if s != null and registry.item(s.id) != null:
				slots[i] = s
			elif s != null:
				push_warning("Inventory: неизвестный предмет '%s' пропущен" % s.id)
	changed.emit()
