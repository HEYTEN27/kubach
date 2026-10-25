class_name Station
extends RefCounted
## Станция ремесла (раздел 5.2 и 6 ТЗ) — процессы во времени без узлов и мира: три набора
## ячеек (входы, топливо, выход), температура, мехи и заслонка, задание с прогрессом в
## игровых минутах, очередь заданий. Состояние целиком лежит в словаре данных блока
## (ChunkColumn.block_entities) и досчитывается за прошедшее время при загрузке колонны.
##
## Режимы (data/stations.json → mode):
## - process — задание выбирается само по тому, что лежит во входах (печь, дробилка, прялка);
## - recipe — игрок выбирает рецепт в окне, входы берутся у него, задание встаёт в очередь
##   (верстак, столяр, наковальня — с баллом мини-игры ковки).
##
## Мини-игры: плавка — держать температуру в «зелёной зоне» [нужная, нужная + ZONE] мехами
## и заслонкой (балл = доля времени в зоне); готовка — снять вовремя (без игрока еда сгорит).
## Авто-режим (настройка «Мини-игры» выкл.): печь сама держит середину зоны, готовка
## останавливается сама, балл — CraftingData.AUTO_SCORE.

const ZONE := 150.0
const AMBIENT := 20.0
## Шаг расчёта (игровые минуты) и предел досчёта (неделя).
const STEP := 0.5
const MAX_CATCHUP := 7.0 * 24.0 * 60.0
const PUMP := 0.35
const BELLOWS_DECAY := 0.3
const QUEUE_MAX := 8
const ALLOY_MAX_UNITS := 16

var data: CraftingData
var def := {}
var kind: StringName
var tier := 1
var inputs: Inventory
var fuel: Inventory
var outputs: Inventory

var temp := AMBIENT
var fuel_left := 0.0
var fuel_heat := 0.0
var bellows := 0.0
var damper := 1.0
## Текущее задание: { recipe, progress, inputs: [стопки-словари], params, score, green, hot, done }.
var job := {}
var queue: Array = []
## Игровое время последнего расчёта (абсолютные минуты) и поворот модели (0…3).
var t := -1.0
var facing := 0
## Авто-режим мини-игр (из настроек; не сохраняется).
var auto := true
var rng := RandomNumberGenerator.new()
# Правила ячеек держим здесь: Callable не удерживает объект, а сами правила инвентарь не знают.
var _fuel_rule: _SlotRule
var _out_rule: _SlotRule


func _init(p_data: CraftingData, p_kind: StringName, p_tier: int = 1) -> void:
	data = p_data
	kind = p_kind
	tier = p_tier
	def = data.station(kind)
	rng.randomize()
	var reg := data.registry
	inputs = Inventory.new(reg, int(def.get("inputs", 0)), "station_in")
	fuel = Inventory.new(reg, int(def.get("fuel", 0)), "station_fuel")
	outputs = Inventory.new(reg, int(def.get("outputs", 0)), "station_out")
	_fuel_rule = _SlotRule.new(data, &"fuel")
	_out_rule = _SlotRule.new(data, &"out")
	fuel.accept_filter = _fuel_rule.check
	outputs.accept_filter = _out_rule.check


func is_process() -> bool:
	return String(def.get("mode", "process")) == "process"


func has_heat() -> bool:
	return bool(def.get("heat", false))


## Горит ли топливо (свет, тепло, частицы).
func lit() -> bool:
	return has_heat() and fuel_left > 0.0


## Тепло для окружения (EnvironmentProbe), пока горит.
func warmth() -> float:
	return float(def.get("warmth", 0.0)) if lit() else 0.0


## Наибольшая температура с мехами.
func max_heat() -> float:
	return float(def.get("max_heat", 0.0))


func current_recipe() -> Dictionary:
	return data.recipe(StringName(job.get("recipe", ""))) if not job.is_empty() else {}


## Доля готовности задания 0…1 (у готовки может быть больше 1 — пережаривается).
func progress() -> float:
	var r := current_recipe()
	if r.is_empty():
		return 0.0
	return float(job.get("progress", 0.0)) / maxf(0.01, float(r.get("time", 1.0)))


# --- управление ------------------------------------------------------------------------------

## Качнуть мехи (мини-игра плавки).
func pump() -> void:
	if float(def.get("bellows", 0.0)) > 0.0:
		bellows = minf(1.0, bellows + PUMP)


func set_damper(v: float) -> void:
	damper = clampf(v, 0.0, 1.0)


## Снять с огня сейчас (мини-игра готовки). true — снято.
func take_cook() -> bool:
	var r := current_recipe()
	if r.is_empty() or String(r.get("op", "")) != "cook" or job.get("done", false):
		return false
	_finish()
	return true


## Поставить задание рецепта в очередь (режим recipe): входы уже списаны у игрока.
func enqueue(r: Dictionary, consumed: Array[ItemStack], score: float, params: Dictionary = {}) -> bool:
	if queue.size() >= QUEUE_MAX:
		return false
	var ins := []
	for s in consumed:
		ins.append(s.to_dict())
	var p := params.duplicate()
	queue.append({ "recipe": String(r["id"]), "inputs": ins, "score": score, "params": _params_to_save(p) })
	if job.is_empty():
		_start_next()
	return true


## Собрать инструмент из частей во входах 0…2 (верстак). Пусто — получилось, иначе причина.
func start_assembly(r: Dictionary) -> String:
	var why := ToolAssembly.check(data, StringName(r["tool_type"]), inputs.get_stack(0), inputs.get_stack(1),
		inputs.get_stack(2), r.get("categories", []))
	if why != "":
		return why
	if queue.size() >= QUEUE_MAX:
		return "очередь заполнена"
	var parts := {}
	var keys := ["head", "handle", "binding"]
	for i in 3:
		var s := inputs.get_stack(i)
		parts[keys[i]] = s.split(1)
		inputs.set_stack(i, s if s.count > 0 else null)
	enqueue(r, [], 0.0, { "parts": parts, "station_bonus": float(def.get("quality_bonus", 0.0)) })
	return ""


## Разобрать инструмент из входа 0.
func start_salvage(r: Dictionary) -> String:
	var s := inputs.get_stack(0)
	var d := data.registry.item(s.id) if s != null else null
	if d == null or not d.is_assembled():
		return "положите инструмент из частей в первую ячейку"
	inputs.set_stack(0, null)
	enqueue(r, [s], 0.0)
	return ""


## Починить инструмент из входа 0 материалом consumed (units единиц).
func start_repair(r: Dictionary, consumed: Array[ItemStack], units: int) -> String:
	var s := inputs.get_stack(0)
	if s == null:
		return "положите инструмент в первую ячейку"
	inputs.set_stack(0, null)
	enqueue(r, consumed, 0.0, { "tool": s, "units": units })
	return ""


# --- ход времени -----------------------------------------------------------------------------

## Досчитать до момента now (абсолютные игровые минуты). ctx: water (вода рядом).
## Возвращает события: [{ type: "done", recipe, outputs }].
func advance_to(now: float, ctx: Dictionary = {}) -> Array:
	if t < 0.0:
		t = now
		if job.is_empty():
			_start_next()
		return []
	var dt := clampf(now - t, 0.0, MAX_CATCHUP)
	t = now
	return advance(dt, ctx)


func advance(minutes: float, ctx: Dictionary = {}) -> Array:
	var events := []
	var left := minutes
	# Долгий досчёт — крупнее шаг (ограничение числа шагов).
	var step := maxf(STEP, minutes / 2000.0)
	while left > 0.0001:
		var dt := minf(step, left)
		_step(dt, ctx, events)
		left -= dt
	return events


func _step(dt: float, ctx: Dictionary, events: Array) -> void:
	if job.is_empty():
		_start_next()
	var r := current_recipe()
	var need_heat := float(r.get("heat", 0.0)) if not r.is_empty() else 0.0
	if has_heat():
		_heat_step(dt, need_heat, not r.is_empty())
	if r.is_empty():
		return
	if job.get("done", false):
		_try_output(events)
		return
	if bool(def.get("needs_water", false)) and not ctx.get("water", true):
		return
	var hot := temp >= need_heat - 0.01
	if String(r.get("minigame", "none")) == "smelt" and hot:
		job["hot"] = float(job.get("hot", 0.0)) + dt
		if temp <= need_heat + ZONE:
			job["green"] = float(job.get("green", 0.0)) + dt
	if not hot:
		return
	job["progress"] = float(job.get("progress", 0.0)) + dt
	var time := float(r.get("time", 1.0)) * float(job.get("params", {}).get("units", 1) if String(r.get("op", "")) == "alloy" else 1)
	var p := float(job["progress"])
	if String(r.get("op", "")) == "cook":
		var c: Dictionary = r.get("cook", {})
		var end := time if auto else time * float(c.get("burnt_at", 1.8))
		if p >= end:
			_finish()
			_try_output(events)
	elif p >= time:
		_finish()
		_try_output(events)


func _heat_step(dt: float, need_heat: float, busy: bool) -> void:
	var want_burn := busy or bool(def.get("always_burn", false)) or (is_process() and not inputs.is_empty())
	if fuel_left <= 0.0 and want_burn:
		_take_fuel()
	var boost := float(def.get("bellows", 0.0))
	if auto and busy and need_heat > 0.0 and fuel_left > 0.0:
		# Авто: держим середину зелёной зоны заслонкой и мехами.
		var desired := minf(need_heat + ZONE * 0.5, max_heat())
		var fh := minf(fuel_heat, max_heat())
		if fh >= desired:
			damper = clampf((desired - AMBIENT) / maxf(1.0, fh - AMBIENT), 0.0, 1.0)
			bellows = 0.0
		else:
			damper = 1.0
			bellows = clampf((desired - fh) / boost, 0.0, 1.0) if boost > 0.0 else 0.0
	var target := AMBIENT
	if fuel_left > 0.0:
		fuel_left = maxf(0.0, fuel_left - dt * (0.5 + 0.5 * damper + 0.4 * bellows))
		target = AMBIENT + (minf(fuel_heat, max_heat()) - AMBIENT) * damper + bellows * boost
		target = minf(target, max_heat())
	var rate := float(def.get("heat_rate", 60.0)) if target > temp else float(def.get("cool_rate", 20.0))
	temp = move_toward(temp, target, rate * dt)
	if not auto:
		bellows = maxf(0.0, bellows - BELLOWS_DECAY * dt)


func _take_fuel() -> void:
	for i in fuel.size():
		var s := fuel.get_stack(i)
		if s == null:
			continue
		var f := data.fuel_of(s.id)
		if f.is_empty():
			continue
		fuel_left = float(f.get("minutes", 1.0))
		fuel_heat = float(f.get("heat", 500.0))
		s.count -= 1
		fuel.set_stack(i, s if s.count > 0 else null)
		return


## Новое задание: из очереди (recipe) или по входам (process).
func _start_next() -> void:
	if not queue.is_empty():
		var q: Dictionary = queue.pop_front()
		job = { "recipe": q["recipe"], "progress": 0.0, "inputs": q["inputs"], "score": q["score"], "params": q["params"] }
		return
	if not is_process() or inputs.is_empty():
		return
	for r: Dictionary in _process_recipes():
		var j := _try_start(r)
		if not j.is_empty():
			job = j
			return


## Рецепты станции: сплавы раньше обычной плавки (медь + олово — это бронза, а не медь).
func _process_recipes() -> Array:
	var rs: Array = data.recipes_for(kind)
	var alloys := []
	var rest := []
	for r: Dictionary in rs:
		if float(r.get("heat", 0.0)) > max_heat() + float(def.get("bellows", 0.0)) + 0.01 and has_heat():
			continue
		(alloys if String(r.get("op", "")) == "alloy" else rest).append(r)
	return alloys + rest


func _try_start(r: Dictionary) -> Dictionary:
	var op := String(r.get("op", "craft"))
	var consumed: Array[ItemStack] = []
	var params := {}
	match op:
		"alloy":
			var a: Dictionary = {}
			for al in data.alloys:
				if String(al["id"]) == String(r.get("tool_type", "")):
					a = al
			var stacks := []
			for i in inputs.size():
				stacks.append(inputs.get_stack(i))
			if a.is_empty() or not Alloy.analyze(a, stacks)["valid"]:
				return {}
			var info := Alloy.analyze(a, stacks)
			# Берём всё (не больше ALLOY_MAX_UNITS единиц), сохраняя пропорции входов.
			var k := minf(1.0, float(ALLOY_MAX_UNITS) / float(info["units"]))
			var units := 0
			for i in inputs.size():
				var s := inputs.get_stack(i)
				if s == null:
					continue
				var n := maxi(1, floori(s.count * k))
				consumed.append(s.split(n))
				units += n
				inputs.set_stack(i, s if s.count > 0 else null)
			var real := Alloy.analyze(a, consumed)
			params = { "alloy_id": a["id"], "units": units, "factor": real["factor"] }
		"quench":
			var part_i := -1
			var oil_i := -1
			for i in inputs.size():
				var s := inputs.get_stack(i)
				if s == null:
					continue
				if data.has_tag(s.id, "quench_oil"):
					oil_i = i
				elif _is_head(s, true) and not s.data.get("quenched", false):
					part_i = i
			if part_i < 0:
				return {}
			var ps := inputs.get_stack(part_i)
			consumed.append(ps.split(1))
			inputs.set_stack(part_i, ps if ps.count > 0 else null)
			params["medium"] = "water"
			if oil_i >= 0:
				var os := inputs.get_stack(oil_i)
				os.count -= 1
				inputs.set_stack(oil_i, os if os.count > 0 else null)
				params["medium"] = "oil"
		"sharpen":
			for i in inputs.size():
				var s := inputs.get_stack(i)
				if s != null and _is_head(s, false) and not s.data.get("sharpened", false):
					consumed.append(s.split(1))
					inputs.set_stack(i, s if s.count > 0 else null)
					break
			if consumed.is_empty():
				return {}
		"dye":
			var cloth_i := -1
			var dye_i := -1
			for i in inputs.size():
				var s := inputs.get_stack(i)
				if s == null:
					continue
				var d := data.registry.item(s.id)
				if d.dye != "":
					dye_i = i
				elif d.tags.has("cloth"):
					cloth_i = i
			if cloth_i < 0 or dye_i < 0:
				return {}
			for i in [cloth_i, dye_i]:
				var s := inputs.get_stack(i)
				consumed.append(s.split(1))
				inputs.set_stack(i, s if s.count > 0 else null)
		_:
			var ins: Array = r.get("inputs", [])
			if ins.is_empty() or not Ingredients.can_take(data, ins, [inputs]):
				return {}
			consumed = Ingredients.take(data, ins, [inputs])
	var dicts := []
	for s in consumed:
		dicts.append(s.to_dict())
	return { "recipe": String(r["id"]), "progress": 0.0, "inputs": dicts, "score": -1.0, "params": params }


## Навершие (часть слота head); only_metal — только металлическое (закалка).
func _is_head(s: ItemStack, only_metal: bool) -> bool:
	var d := data.registry.item(s.id)
	if d == null or not d.is_part() or not d.tags.has("head"):
		return false
	if only_metal:
		var m := data.material(data.material_of(s))
		return not m.is_empty() and String(m["category"]) == "metal"
	return true


## Задание закончилось: считаем выходы (кладём в job.outputs, ждут места в выходе).
func _finish() -> void:
	var r := current_recipe()
	var consumed: Array[ItemStack] = []
	for d: Dictionary in job.get("inputs", []):
		var s := ItemStack.from_dict(d)
		if s != null:
			consumed.append(s)
	var params := _params_from_save(job.get("params", {}))
	params["rng"] = rng
	var game := float(job.get("score", -1.0))
	if game < 0.0:
		game = _game_score(r)
	var bonus := float(def.get("quality_bonus", 0.0)) + 0.02 * maxi(0, tier - 1)
	var sc := game if String(r.get("op", "")) == "forge_part" and float(job.get("score", -1.0)) >= 0.0 \
			else Crafting.score(data, consumed, game, bonus)
	if String(r.get("op", "")) == "forge_part" and float(job.get("score", -1.0)) >= 0.0:
		sc = Crafting.score(data, consumed, game, bonus)
	if String(r.get("op", "")) == "cook":
		params["zone"] = cook_zone(r, progress())
	if String(r.get("op", "")) == "alloy":
		for al in data.alloys:
			if String(al["id"]) == String(params.get("alloy_id", "")):
				params["alloy"] = al
	var outs := Crafting.outputs(data, r, consumed, sc, params)
	var dicts := []
	for s in outs:
		dicts.append(s.to_dict())
	job["done"] = true
	job["outputs"] = dicts


## Балл мини-игры задания без явного балла: плавка — доля времени в зоне, иначе обычный.
func _game_score(r: Dictionary) -> float:
	match String(r.get("minigame", "none")):
		"smelt":
			if auto:
				return CraftingData.AUTO_SCORE
			var hot := float(job.get("hot", 0.0))
			return float(job.get("green", 0.0)) / hot if hot > 0.0 else 0.0
		"cook", "forge":
			return CraftingData.AUTO_SCORE
	return CraftingData.PLAIN_SCORE


## Зона прожарки по доле времени: under, perfect, over, burnt.
static func cook_zone(r: Dictionary, k: float) -> String:
	var c: Dictionary = r.get("cook", {})
	if k < float(c.get("perfect_from", 0.9)):
		return "under"
	if k <= float(c.get("perfect_to", 1.25)):
		return "perfect"
	if k < float(c.get("burnt_at", 1.8)):
		return "over"
	return "burnt"


func _try_output(events: Array) -> void:
	var outs: Array[ItemStack] = []
	for d: Dictionary in job.get("outputs", []):
		var s := ItemStack.from_dict(d)
		if s != null:
			outs.append(s)
	# Влезает ли всё: пробуем на копии.
	var test := Inventory.new(data.registry, outputs.size())
	for i in outputs.size():
		var cur := outputs.get_stack(i)
		test.slots[i] = cur.copy() if cur != null else null
	for s in outs:
		if test.add(s.copy()) > 0:
			return
	for s in outs:
		_add_out(s)
	events.append({ "type": "done", "recipe": job.get("recipe", ""), "outputs": job.get("outputs", []) })
	job = {}


## Положить в выход в обход фильтра (игрок туда класть не может, станция — может).
func _add_out(s: ItemStack) -> void:
	var f := outputs.accept_filter
	outputs.accept_filter = Callable()
	outputs.add(s)
	outputs.accept_filter = f


# --- состояние ----------------------------------------------------------------------------------

## Почему станция не работает (пусто — работает или нечего делать).
func blocker(ctx: Dictionary = {}) -> String:
	var r := current_recipe()
	if r.is_empty():
		return ""
	if job.get("done", false):
		return "Выход занят — заберите готовое"
	if bool(def.get("needs_water", false)) and not ctx.get("water", true):
		return "Нужна вода рядом (2 блока)"
	var need := float(r.get("heat", 0.0))
	if has_heat() and temp < need:
		if fuel_left <= 0.0 and fuel.is_empty():
			return "Нет топлива"
		return "Мало жара: %d / %d °C" % [roundi(temp), roundi(need)]
	return ""


## Всё, что выпадет при поломке: ячейки, входы текущего задания и очереди.
func all_items() -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for inv: Inventory in [inputs, fuel, outputs]:
		for i in inv.size():
			if inv.get_stack(i) != null:
				out.append(inv.get_stack(i))
	var jobs := queue.duplicate()
	if not job.is_empty():
		jobs.push_front(job)
	for j: Dictionary in jobs:
		var key := "outputs" if j.get("done", false) else "inputs"
		for d: Dictionary in j.get(key, []):
			var s := ItemStack.from_dict(d)
			if s != null:
				out.append(s)
		var p: Dictionary = j.get("params", {})
		if not j.get("done", false):
			for pk: String in ["tool"]:
				if p.has(pk) and p[pk] is Dictionary:
					out.append(ItemStack.from_dict(p[pk]))
			if p.get("parts") is Dictionary:
				for k: String in p["parts"]:
					out.append(ItemStack.from_dict(p["parts"][k]))
	return out


func to_dict() -> Dictionary:
	return {
		"type": "station", "kind": String(kind), "tier": tier,
		"in": inputs.to_array(), "fuel": fuel.to_array(), "out": outputs.to_array(),
		"temp": temp, "fuel_left": fuel_left, "fuel_heat": fuel_heat, "bellows": bellows, "damper": damper,
		"job": job, "queue": queue, "t": t, "facing": facing,
	}


func from_dict(d: Dictionary) -> void:
	inputs.from_array(d.get("in", []))
	fuel.from_array(d.get("fuel", []))
	outputs.from_array(d.get("out", []))
	temp = float(d.get("temp", AMBIENT))
	fuel_left = float(d.get("fuel_left", 0.0))
	fuel_heat = float(d.get("fuel_heat", 0.0))
	bellows = float(d.get("bellows", 0.0))
	damper = float(d.get("damper", 1.0))
	job = d.get("job", {})
	queue = d.get("queue", [])
	t = float(d.get("t", -1.0))
	facing = int(d.get("facing", 0))


## Пусто ли (нечего сохранять, кроме поворота).
func is_idle_empty() -> bool:
	return inputs.is_empty() and fuel.is_empty() and outputs.is_empty() and job.is_empty() and queue.is_empty() \
			and fuel_left <= 0.0


# Параметры заданий с ItemStack внутри — в словари и обратно (для сохранения).
static func _params_to_save(p: Dictionary) -> Dictionary:
	var out := {}
	for k: String in p:
		var v: Variant = p[k]
		if v is ItemStack:
			out[k] = (v as ItemStack).to_dict()
		elif v is Dictionary and k == "parts":
			var pp := {}
			for pk: String in v:
				pp[pk] = (v[pk] as ItemStack).to_dict() if v[pk] is ItemStack else v[pk]
			out[k] = pp
		elif v is RandomNumberGenerator:
			continue
		else:
			out[k] = v
	return out


static func _params_from_save(p: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	if p.get("tool") is Dictionary:
		out["tool"] = ItemStack.from_dict(p["tool"])
	if p.get("parts") is Dictionary:
		var pp := {}
		for k: String in p["parts"]:
			pp[k] = ItemStack.from_dict(p["parts"][k])
		out["parts"] = pp
	return out


## Правило ячеек (без ссылки на инвентарь — иначе цикл ссылок).
class _SlotRule:
	extends RefCounted
	var data: CraftingData
	var role: StringName

	func _init(p_data: CraftingData, p_role: StringName) -> void:
		data = p_data
		role = p_role

	func check(_i: int, s: ItemStack) -> bool:
		if role == &"out":
			return false
		if role == &"fuel":
			return not data.fuel_of(s.id).is_empty()
		return true
