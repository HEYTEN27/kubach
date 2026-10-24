class_name InventoryOps
extends RefCounted
## Операции окна инвентаря с «предметом на курсоре» (раздел 4.4 ТЗ):
## - ЛКМ: взять стопку / положить / сложить / поменять местами;
## - ПКМ: взять половину / положить одну штуку;
## - протяжка с зажатой ПКМ: по одной штуке в каждую ячейку;
## - Shift+клик: быстрый перенос в другую часть (хотбар ↔ инвентарь, сундук ↔ игрок,
##   надеть/снять экипировку);
## - двойной клик: собрать на курсор все такие же предметы;
## - сортировка, корзина (творческий режим), «сложить похожее» в открытый сундук.
## Выброшенное наружу передаётся в dropped (мир превращает его в предметы на земле).

signal dropped(stack: ItemStack)

var player: PlayerInventory
## Открытый контейнер (сундук) или null.
var container: Inventory
var cursor: ItemStack
var creative := false
var _drag_visited := {}


func _init(p_player: PlayerInventory) -> void:
	player = p_player


func resolve(name: String) -> Inventory:
	match name:
		"hotbar":
			return player.hotbar
		"main":
			return player.main
		"backpack":
			return player.backpack
		"equipment":
			return player.equipment
		"container":
			return container
	return null


## Выполнить действие слоя действий. true — что-то изменилось.
func execute(a: InventoryAction) -> bool:
	var inv := resolve(a.inv)
	match a.op:
		InventoryAction.Op.LEFT:
			return inv != null and left_click(inv, a.index)
		InventoryAction.Op.RIGHT:
			return inv != null and right_click(inv, a.index)
		InventoryAction.Op.RIGHT_DRAG:
			return inv != null and right_drag(inv, a.index)
		InventoryAction.Op.SHIFT:
			return inv != null and shift_click(inv, a.index)
		InventoryAction.Op.DOUBLE:
			return inv != null and double_click(inv, a.index)
		InventoryAction.Op.SORT:
			if inv == null:
				return false
			inv.sort()
			return true
		InventoryAction.Op.TRASH:
			return trash()
		InventoryAction.Op.DROP_CURSOR:
			return drop_cursor(a.amount)
		InventoryAction.Op.DROP_SLOT:
			return inv != null and drop_slot(inv, a.index, a.amount)
		InventoryAction.Op.TAKE_CREATIVE:
			return take_creative(a.item_id, a.amount)
		InventoryAction.Op.DEPOSIT_SIMILAR:
			return deposit_similar()
		InventoryAction.Op.HOTBAR_SWAP:
			return inv != null and hotbar_swap(inv, a.index, a.amount)
	return false


func left_click(inv: Inventory, i: int) -> bool:
	var slot := inv.get_stack(i)
	end_drag()
	if cursor == null:
		if slot == null:
			return false
		cursor = slot
		inv.set_stack(i, null)
		return true
	if not inv.accepts(i, cursor):
		return false
	if slot == null:
		inv.set_stack(i, cursor)
		cursor = null
		return true
	if slot.can_merge(cursor):
		var limit := inv.max_stack(slot.id)
		var n := mini(limit - slot.count, cursor.count)
		if n <= 0:
			return false
		slot.count += n
		cursor.count -= n
		if cursor.count == 0:
			cursor = null
		inv.set_stack(i, slot)
		return true
	# Поменять местами.
	inv.set_stack(i, cursor)
	cursor = slot
	return true


func right_click(inv: Inventory, i: int) -> bool:
	var slot := inv.get_stack(i)
	if cursor == null:
		if slot == null:
			return false
		var half := ceili(slot.count / 2.0)
		cursor = slot.split(half)
		inv.set_stack(i, slot if slot.count > 0 else null)
		return true
	return _place_one(inv, i)


## Протяжка с зажатой ПКМ: по одной штуке в каждую новую ячейку.
func right_drag(inv: Inventory, i: int) -> bool:
	var key := [inv, i]
	if _drag_visited.has(key) or cursor == null:
		return false
	_drag_visited[key] = true
	return _place_one(inv, i)


## Конец протяжки (кнопку отпустили).
func end_drag() -> void:
	_drag_visited.clear()


func _place_one(inv: Inventory, i: int) -> bool:
	var slot := inv.get_stack(i)
	if not inv.accepts(i, cursor):
		return false
	if slot == null:
		inv.set_stack(i, cursor.split(1))
	elif slot.can_merge(cursor) and slot.count < inv.max_stack(slot.id):
		slot.count += 1
		cursor.count -= 1
		inv.set_stack(i, slot)
	else:
		return false
	if cursor.count == 0:
		cursor = null
	return true


## Куда переносит Shift+клик из хранилища inv.
func quick_targets(inv: Inventory) -> Array[Inventory]:
	if container != null:
		if inv == container:
			return [player.hotbar, player.main, player.backpack]
		return [container]
	if inv == player.hotbar:
		return [player.main, player.backpack]
	if inv == player.equipment:
		return [player.main, player.backpack, player.hotbar]
	return [player.hotbar]


func shift_click(inv: Inventory, i: int) -> bool:
	var slot := inv.get_stack(i)
	if slot == null:
		return false
	end_drag()
	# Надеть: предмет с экипировочным слотом из любого хранилища игрока — в свободный слот.
	if container == null and inv != player.equipment:
		var d := player.registry.item(slot.id)
		if d != null and d.equip != ItemDef.EQUIP_NONE and d.kind != &"block":
			for e in player.equipment.size():
				if player.equipment.slot_kinds[e] == d.equip and player.equipment.get_stack(e) == null:
					inv.set_stack(i, null)
					player.equipment.set_stack(e, slot)
					return true
	var before := slot.count
	for t in quick_targets(inv):
		if t == null or slot.count == 0:
			continue
		t.add(slot)
	if slot.count == before:
		return false
	inv.set_stack(i, slot if slot.count > 0 else null)
	return true


## Двойной клик: собрать на курсор все такие же предметы из окна.
func double_click(inv: Inventory, i: int) -> bool:
	var target := cursor if cursor != null else inv.get_stack(i)
	if target == null:
		return false
	if cursor == null:
		cursor = target
		inv.set_stack(i, null)
	var limit := inv.max_stack(cursor.id)
	var changed := false
	for src: Inventory in [player.hotbar, player.main, player.backpack, container]:
		if src == null:
			continue
		for k in src.size():
			if cursor.count >= limit:
				break
			var s := src.get_stack(k)
			if s == null or not s.can_merge(cursor):
				continue
			var n := mini(limit - cursor.count, s.count)
			s.count -= n
			cursor.count += n
			src.set_stack(k, s if s.count > 0 else null)
			changed = true
	return changed


func trash() -> bool:
	if cursor == null or not creative:
		return false
	cursor = null
	return true


## Выбросить с курсора (amount 0 — всё).
func drop_cursor(amount: int = 0) -> bool:
	if cursor == null:
		return false
	var n := cursor.count if amount <= 0 else mini(amount, cursor.count)
	var out := cursor.split(n)
	if cursor.count == 0:
		cursor = null
	dropped.emit(out)
	return true


## Выбросить из ячейки (Q в окне или из руки): amount 0 — всю стопку.
func drop_slot(inv: Inventory, i: int, amount: int = 1) -> bool:
	var s := inv.get_stack(i)
	if s == null:
		return false
	var n := s.count if amount <= 0 else mini(amount, s.count)
	var out := s.split(n)
	inv.set_stack(i, s if s.count > 0 else null)
	dropped.emit(out)
	return true


## Творческий каталог: взять предмет на курсор (amount 0 — полную стопку).
func take_creative(id: StringName, amount: int = 0) -> bool:
	if not creative:
		return false
	var d := player.registry.item(id)
	if d == null:
		return false
	var n := d.stack if amount <= 0 else mini(amount, d.stack)
	if cursor != null and cursor.id == id and cursor.data == ItemStack.create(d, 1).data:
		cursor.count = mini(d.stack, cursor.count + n)
		return true
	cursor = ItemStack.create(d, n)
	return true


## Клавиша 1…9 над ячейкой: поменять её с ячейкой хотбара.
func hotbar_swap(inv: Inventory, i: int, hb: int) -> bool:
	if hb < 0 or hb >= player.hotbar.size() or (inv == player.hotbar and i == hb):
		return false
	var a := inv.get_stack(i)
	var b := player.hotbar.get_stack(hb)
	if not inv.accepts(i, b):
		return false
	inv.set_stack(i, b)
	player.hotbar.set_stack(hb, a)
	return true


## «Сложить всё похожее»: в открытый контейнер уходят предметы игрока, которые там уже есть.
func deposit_similar() -> bool:
	if container == null:
		return false
	var ids := {}
	for s: ItemStack in container.slots:
		if s != null:
			ids[s.id] = true
	var moved := false
	for src: Inventory in [player.main, player.backpack]:
		for k in src.size():
			var s := src.get_stack(k)
			if s == null or not ids.has(s.id):
				continue
			var before := s.count
			container.add(s)
			if s.count != before:
				moved = true
				src.set_stack(k, s if s.count > 0 else null)
	return moved


## Окно закрыто: предмет с курсора возвращается в инвентарь, а что не влезло — выбрасывается.
func close() -> void:
	end_drag()
	if cursor == null:
		return
	var rest := player.add(cursor)
	if rest > 0:
		dropped.emit(cursor)
	cursor = null
