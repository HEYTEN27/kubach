class_name LightningTarget
extends RefCounted
## Куда бьёт молния (раздел 3.3 ТЗ): чаще в высокие точки и металл, громоотвод перехватывает
## удары в радиусе ROD_RADIUS. Выбирается случайный центр недалеко от игрока, вокруг него —
## самая высокая точка (металл считается выше на METAL_BONUS блоков).

const SEARCH := 6
const STEP := 2
const ROD_RADIUS := 24
const METAL_BONUS := 6


## Точка удара (верхний блок) или Vector3i(0, MIN_Y−1, 0), если вокруг ничего не загружено.
## rods — известные громоотводы (WeatherSystem следит за установкой и загрузкой колонн).
static func pick(world: World, cx: int, cz: int, rng: RandomNumberGenerator, radius: int = 96,
		rods: Array = []) -> Vector3i:
	var a := rng.randf() * TAU
	var r := rng.randf_range(12.0, float(radius))
	var center := Vector2i(cx + roundi(cos(a) * r), cz + roundi(sin(a) * r))
	var rod := _find_rod(world, center, rods)
	if rod.y >= WorldConst.MIN_Y:
		return rod
	var best := Vector3i(0, WorldConst.MIN_Y - 1, 0)
	var best_score := -INF
	for dz in range(-SEARCH, SEARCH + 1, STEP):
		for dx in range(-SEARCH, SEARCH + 1, STEP):
			var x := center.x + dx
			var z := center.y + dz
			var y := top_y(world, x, z)
			if y < WorldConst.MIN_Y:
				continue
			var b := world.get_block(x, y, z)
			var score: float = float(y) + (float(METAL_BONUS) if _is_metal(world, b) else 0.0) + rng.randf() * 0.5
			if score > best_score:
				best_score = score
				best = Vector3i(x, y, z)
	return best


static func top_y(world: World, x: int, z: int) -> int:
	var col: ChunkColumn = world.chunks.columns.get(Vector2i(x >> 4, z >> 4))
	if col == null:
		return WorldConst.MIN_Y - 1
	return col.top_block_y(x & 15, z & 15)


static func _is_metal(world: World, b: int) -> bool:
	var def := world.registry.block_by_num(b) if b > 0 else null
	return def != null and def.material == &"metal"


## Ближайший громоотвод в радиусе, стоящий на самом верху своей колонны.
static func _find_rod(world: World, center: Vector2i, rods: Array) -> Vector3i:
	var rod := world.registry.block_num(&"lightning_rod")
	var best := Vector3i(0, WorldConst.MIN_Y - 1, 0)
	var best_d := INF
	for p: Vector3i in rods:
		var d := float((p.x - center.x) * (p.x - center.x) + (p.z - center.y) * (p.z - center.y))
		if d > ROD_RADIUS * ROD_RADIUS or d >= best_d:
			continue
		if world.get_block(p.x, p.y, p.z) == rod and top_y(world, p.x, p.z) == p.y:
			best_d = d
			best = p
	return best
