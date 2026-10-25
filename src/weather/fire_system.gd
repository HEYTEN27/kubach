class_name FireSystem
extends RefCounted
## Огонь (раздел 3.3 ТЗ: молния поджигает дерево и траву, огонь распространяется) без узлов.
## Блок «fire» стоит в воздухе рядом с горючим (block_flammable): каждую игровую минуту с
## шансом перекидывается на воздух у соседнего горючего и пережигает соседние горючие блоки
## (листва, брёвна, доски, трава исчезают). Без горючего рядом гаснет; дождь под открытым
## небом тушит. Число огней ограничено (MAX_FIRES) — лесной пожар не съест кадр.

const MAX_FIRES := 160
const SPREAD_PER_MIN := 0.12
const BURN_PER_MIN := 0.06
const LIFE_MIN := 6.0
const LIFE_MAX := 14.0
const DIRS: Array[Vector3i] = [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var world: World
var fire_num := 0
var rng := RandomNumberGenerator.new()
## Vector3i → оставшаяся жизнь (игровые минуты).
var fires := {}


func _init(p_world: World) -> void:
	world = p_world
	fire_num = maxi(0, world.registry.block_num(&"fire"))
	rng.randomize()


func flammable(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	return b > 0 and world.registry.block_flammable[b] == 1


## Можно ли поставить огонь в клетку: воздух, растение или тонкий слой (не жидкость).
func _free(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	if b < 0:
		return false
	if b == 0:
		return true
	var reg := world.registry
	return reg.block_shape[b] != BlockDef.SHAPE_CUBE and reg.block_render[b] != BlockDef.RENDER_LIQUID \
			and reg.block_model[b] == 0


## Поджечь клетку p (или клетку над горючим p). Возвращает поставленную позицию или null.
func ignite(p: Vector3i) -> Variant:
	if fires.size() >= MAX_FIRES or fire_num <= 0:
		return null
	var at := p
	if flammable(p) and world.registry.block_shape[world.get_block(p.x, p.y, p.z)] == BlockDef.SHAPE_CUBE:
		at = p + Vector3i.UP
	if not _free(at):
		return null
	if not _near_fuel(at) and not flammable(at):
		return null
	if not world.set_block(at.x, at.y, at.z, fire_num):
		return null
	fires[at] = rng.randf_range(LIFE_MIN, LIFE_MAX)
	return at


func _near_fuel(p: Vector3i) -> bool:
	for d in DIRS:
		if flammable(p + d):
			return true
	return false


## Подхватить уже стоящий огонь (загрузка колонны).
func register(p: Vector3i) -> void:
	if not fires.has(p) and fires.size() < MAX_FIRES:
		fires[p] = rng.randf_range(LIFE_MIN, LIFE_MAX)


## Шаг minutes игровых минут. rain_at(p: Vector3i) -> bool — идёт ли дождь над клеткой.
## Возвращает число изменённых клеток.
func tick(minutes: float, rain_at: Callable = Callable()) -> int:
	var changes := 0
	for p: Vector3i in fires.keys():
		if world.get_block(p.x, p.y, p.z) != fire_num:
			fires.erase(p)
			continue
		if rain_at.is_valid() and rain_at.call(p):
			_put_out(p)
			changes += 1
			continue
		fires[p] = float(fires[p]) - minutes
		var fuel: Array[Vector3i] = []
		for d in DIRS:
			if flammable(p + d):
				fuel.append(p + d)
		for f in fuel:
			# Перекинуться: на свободную клетку рядом с горючим соседом.
			if rng.randf() < 1.0 - pow(1.0 - SPREAD_PER_MIN, minutes):
				var d: Vector3i = DIRS[rng.randi() % DIRS.size()]
				if ignite(f + d) != null:
					changes += 1
			# Пережечь соседа.
			if rng.randf() < 1.0 - pow(1.0 - BURN_PER_MIN, minutes):
				world.set_block(f.x, f.y, f.z, 0)
				changes += 1
		if fuel.is_empty() or float(fires[p]) <= 0.0:
			_put_out(p)
			changes += 1
	return changes


func _put_out(p: Vector3i) -> void:
	fires.erase(p)
	if world.get_block(p.x, p.y, p.z) == fire_num:
		world.set_block(p.x, p.y, p.z, 0)
