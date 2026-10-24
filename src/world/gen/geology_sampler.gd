class_name GeologySampler
extends RefCounted
## Геологические провинции (data/geology.json): крупные ячейки регионального шума. В каждой —
## осадочный чехол и фундамент из слоёв переменной толщины и глубинный слой ниже deep_top.

var count := 0
var ids: Array[StringName] = []
## По провинции: [PackedInt32Array блоки, PackedInt32Array мин, PackedInt32Array макс] (чехол + фундамент).
var layers: Array = []
var deep_block := PackedInt32Array()
var deep_top := PackedInt32Array()
var deep_noise := PackedInt32Array()
var _cum_weight := PackedFloat32Array()
var _n_province: FastNoiseLite
var _n_thick: FastNoiseLite


func _init(registry: ContentRegistry, world_seed: int, province_cfg: Dictionary, strata_cfg: Dictionary) -> void:
	var total := 0.0
	for e in registry.get_entries("geology"):
		count += 1
		ids.append(StringName(e["id"]))
		var blocks := PackedInt32Array()
		var mins := PackedInt32Array()
		var maxs := PackedInt32Array()
		for l: Dictionary in e["sediments"] + e["basement"]:
			blocks.append(registry.block_num(l["block"]))
			mins.append(l["thickness"]["min"])
			maxs.append(l["thickness"]["max"])
		layers.append([blocks, mins, maxs])
		deep_block.append(registry.block_num(e["deep"]))
		deep_top.append(e["deep_top"])
		deep_noise.append(e["deep_noise"])
		total += float(e["weight"])
		_cum_weight.append(total)
	for i in _cum_weight.size():
		_cum_weight[i] /= total
	_n_province = FastNoiseLite.new()
	_n_province.noise_type = FastNoiseLite.TYPE_CELLULAR
	_n_province.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_n_province.cellular_jitter = 0.9
	_n_province.seed = WorldSeed.derive(world_seed, 40)
	_n_province.frequency = province_cfg["frequency"]
	_n_thick = FastNoiseLite.new()
	_n_thick.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_thick.seed = WorldSeed.derive(world_seed, 41)
	_n_thick.frequency = strata_cfg["frequency"]
	_n_thick.fractal_octaves = strata_cfg["octaves"]


## Индекс провинции в точке.
func province_at(x: int, z: int) -> int:
	var v := (_n_province.get_noise_2d(x, z) + 1.0) * 0.5
	for i in _cum_weight.size():
		if v <= _cum_weight[i]:
			return i
	return count - 1


## Толщина слоя `i` провинции в точке (плавно меняется по горизонтали).
func thickness(province: int, i: int, x: int, z: int) -> int:
	var l: Array = layers[province]
	var mins: PackedInt32Array = l[1]
	var maxs: PackedInt32Array = l[2]
	var t := (_n_thick.get_noise_2d(x + i * 977, z - i * 613) + 1.0) * 0.5
	return mins[i] + roundi(t * (maxs[i] - mins[i]))


func deep_top_at(province: int, x: int, z: int) -> int:
	return deep_top[province] + roundi(_n_thick.get_noise_2d(x * 0.5 - 5000, z * 0.5) * deep_noise[province])
