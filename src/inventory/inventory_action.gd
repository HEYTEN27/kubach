class_name InventoryAction
extends GameAction
## Действие с инвентарём для слоя действий (раздел 22): какая операция, над какой ячейкой
## какого хранилища. Хранилища называются строками: hotbar, main, backpack, equipment,
## container (открытый сундук), creative (каталог творческого режима).

enum Op { LEFT, RIGHT, RIGHT_DRAG, SHIFT, DOUBLE, SORT, TRASH, DROP_CURSOR, DROP_SLOT, TAKE_CREATIVE, DEPOSIT_SIMILAR, HOTBAR_SWAP }

var op: Op
var inv := ""
var index := -1
## Для TAKE_CREATIVE — id предмета и количество; для DROP_SLOT — сколько выбросить;
## для HOTBAR_SWAP — номер ячейки хотбара.
var item_id: StringName = &""
var amount := 0


static func make(p_op: Op, p_inv: String = "", p_index: int = -1) -> InventoryAction:
	var a := InventoryAction.new()
	a.type = GameAction.Type.INVENTORY
	a.op = p_op
	a.inv = p_inv
	a.index = p_index
	return a
