class_name GameAction
extends RefCounted
## Команда игрока для слоя действий (раздел 22 ТЗ). Ввод не меняет мир напрямую: игрок
## создаёт действие, а World.execute() проверяет и применяет его. Тот же объект в будущем
## можно отправить по сети на сервер.

enum Type { BREAK_BLOCK, PLACE_BLOCK, INVENTORY, TAKE_FLUID, POUR_FLUID }

var type: Type
var pos: Vector3i
## Числовой ID ставимого блока (для PLACE_BLOCK).
var block := 0
## Поворот ставимой модели (станции): 0…3 × 90° вокруг вертикали.
var facing := 0
## Жидкость (этап 8): номер вида (Registry.block_fluid) и количество уровней для POUR_FLUID.
var fluid := 0
var fluid_amount := 0
## Результат TAKE_FLUID: сколько уровней набрано (источник — всегда полное ведро).
var taken := 0
## Кто выполняет действие; пока всегда локальный игрок.
var actor: StringName = &"local"


static func break_block(p_pos: Vector3i) -> GameAction:
	var a := GameAction.new()
	a.type = Type.BREAK_BLOCK
	a.pos = p_pos
	return a


static func place_block(p_pos: Vector3i, p_block: int, p_facing: int = 0) -> GameAction:
	var a := GameAction.new()
	a.type = Type.PLACE_BLOCK
	a.pos = p_pos
	a.block = p_block
	a.facing = p_facing
	return a


## Набрать жидкость из клетки (ведро): источник не убывает, конечная вода убирается.
static func take_fluid(p_pos: Vector3i) -> GameAction:
	var a := GameAction.new()
	a.type = Type.TAKE_FLUID
	a.pos = p_pos
	return a


## Вылить amount уровней жидкости вида fluid в клетку (воздух, растение или такая же вода).
static func pour_fluid(p_pos: Vector3i, p_fluid: int, p_amount: int) -> GameAction:
	var a := GameAction.new()
	a.type = Type.POUR_FLUID
	a.pos = p_pos
	a.fluid = p_fluid
	a.fluid_amount = p_amount
	return a
