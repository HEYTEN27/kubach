class_name ForgeGame
extends RefCounted
## Мини-игра ковки (раздел 5.3 ТЗ): заготовка — 8 столбиков высотой 0…10, цель — форма части
## (forge_profile в data/parts.json). «Вытяжка» по столбику опускает его и разгоняет металл
## к соседям, «осадка» — наоборот; масса сохраняется. Металл остывает с каждым ударом и со
## временем; удар по холодному (ниже COLD) даёт трещину. «Нагреть» — снова горячий (нужен
## горящий горн рядом). Балл 0…1: близость к форме минус трещины и лишние удары.

const COLUMNS := 8
const START := 5.0
const COLD := 0.3
const HIT_COOL := 0.05
const TIME_COOL := 0.04
const CRACK_PENALTY := 0.12
const STEP := 1.0

var target: PackedFloat32Array
var shape := PackedFloat32Array()
## Жар заготовки 1 (бела) … 0 (остыла).
var heat := 1.0
var strikes := 0
var cracks := 0
var reheats := 0
var finished := false


func _init(p_target: Array) -> void:
	target = PackedFloat32Array(p_target if p_target.size() == COLUMNS else [5, 5, 5, 5, 5, 5, 5, 5])
	shape.resize(COLUMNS)
	shape.fill(START)


## Вытяжка (down = true) или осадка по столбику i.
func strike(i: int, down: bool = true) -> void:
	if finished or i < 0 or i >= COLUMNS:
		return
	strikes += 1
	if heat < COLD:
		cracks += 1
	var d := -STEP if down else STEP
	var neighbors: Array[int] = []
	for j in [i - 1, i + 1]:
		if j >= 0 and j < COLUMNS:
			neighbors.append(j)
	var moved := absf(d)
	# Нельзя опустить ниже 0 или поднять выше 10 — тогда меньше металла сдвигается.
	if down:
		moved = minf(moved, shape[i])
	else:
		var room := 0.0
		for j in neighbors:
			room += shape[j]
		moved = minf(moved, minf(10.0 - shape[i], room))
	if moved <= 0.0 or neighbors.is_empty():
		heat = maxf(0.0, heat - HIT_COOL)
		return
	shape[i] += signf(d) * moved
	var share := moved / neighbors.size()
	for j in neighbors:
		shape[j] = clampf(shape[j] - signf(d) * share, 0.0, 10.0)
	heat = maxf(0.0, heat - HIT_COOL)


## Остывание за реальные секунды.
func cool(seconds: float) -> void:
	heat = maxf(0.0, heat - TIME_COOL * seconds)


func reheat() -> void:
	heat = 1.0
	reheats += 1


## Среднее отклонение от формы.
func error() -> float:
	var e := 0.0
	for i in COLUMNS:
		e += absf(shape[i] - target[i])
	return e / COLUMNS


## Наименьшее число ударов, чтобы дойти до формы (грубая оценка: сдвинутая масса).
func optimal_strikes() -> int:
	var moved := 0.0
	for i in COLUMNS:
		moved += absf(target[i] - START)
	return maxi(1, ceili(moved / 2.0))


func score() -> float:
	var s := clampf(1.0 - error() / 2.5, 0.0, 1.0)
	s -= cracks * CRACK_PENALTY
	s -= maxf(0.0, strikes - optimal_strikes() * 2.0) * 0.01
	return clampf(s, 0.0, 1.0)


func finish() -> float:
	finished = true
	return score()
