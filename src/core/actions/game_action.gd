class_name GameAction
extends RefCounted
## Команда игрока для слоя действий (раздел 22 ТЗ). Ввод не меняет мир напрямую: игрок
## создаёт действие, а World.execute() проверяет и применяет его. Тот же объект в будущем
## можно отправить по сети на сервер.

enum Type { BREAK_BLOCK, PLACE_BLOCK }

var type: Type
var pos: Vector3i
## Числовой ID ставимого блока (для PLACE_BLOCK).
var block := 0
## Кто выполняет действие; пока всегда локальный игрок.
var actor: StringName = &"local"


static func break_block(p_pos: Vector3i) -> GameAction:
	var a := GameAction.new()
	a.type = Type.BREAK_BLOCK
	a.pos = p_pos
	return a


static func place_block(p_pos: Vector3i, p_block: int) -> GameAction:
	var a := GameAction.new()
	a.type = Type.PLACE_BLOCK
	a.pos = p_pos
	a.block = p_block
	return a
