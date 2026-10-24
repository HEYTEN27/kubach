class_name PlayerVitals
extends RefCounted
## Параметры выживания игрока (раздел 4.3 ТЗ): здоровье, голод, жажда, выносливость,
## температура тела, мокрость, запас воздуха, усталость, болезни и баффы со стадиями.
## Чистая логика без узлов и без обращения к миру: окружение приходит словарём из
## EnvironmentProbe, время — реальными секундами (выносливость, воздух, контакт с огнём)
## и игровыми часами (голод, жажда, температура, болезни). Константы — data/survival.json,
## болезни — data/effects.json, множители сложности — data/difficulties.json.
##
## Шкалы: здоровье и выносливость 0..max, голод и жажда 0..100 (100 — сыт/напился),
## мокрость 0..1, усталость 0..100 (100 — валится с ног), температура тела в °C.

## Причины урона (для экрана смерти и звуков).
const CAUSE_STARVE := "starve"
const CAUSE_THIRST := "thirst"
const CAUSE_COLD := "cold"
const CAUSE_HEAT := "heat"
const CAUSE_DROWN := "drown"
const CAUSE_FALL := "fall"
const CAUSE_FIRE := "fire"

## Шаг расчёта сна, игровые часы.
const SLEEP_STEP_H := 0.25
## Выносливость, после которой снова можно бежать, если выдохся.
const RECOVER_STAMINA := 25.0
## Голод/жажда ниже этого — выносливость восстанавливается вдвое медленнее.
const LOW_FOOD := 15.0
## Свежесть ниже этого — еда испорчена.
const SPOILED := 0.25

var cfg := {}
var diff := {}
var effect_defs := {}
var rng := RandomNumberGenerator.new()

var health := 100.0
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var body_temp := 37.0
var wetness := 0.0
var air := 15.0
var fatigue := 0.0
## Активные эффекты: { id, stage, left } (left — часов до конца стадии, −1 — бессрочно).
var effects: Array[Dictionary] = []
var dead := false
var death_cause := ""
## Ощущаемая температура на последнем тике (для HUD).
var perceived := 20.0
var exhausted := false

## Настройки игры: «Болезни», «Температура тела», «Жажда».
var diseases_enabled := true
var temperature_enabled := true
var thirst_enabled := true

var _stamina_delay := 0.0
var _events: Array[Dictionary] = []


## cfg — запись survival, effects — { id → запись effects }, difficulty — запись difficulties.
func _init(p_cfg: Dictionary = {}, p_effects: Dictionary = {}, p_difficulty: Dictionary = {}) -> void:
	cfg = p_cfg
	effect_defs = p_effects
	diff = p_difficulty
	rng.randomize()
	health = health_max()
	stamina = stamina_max()
	body_temp = _c("body_temp_normal", 37.0)
	air = _c("air_max_s", 15.0)


## Собрать из реестра: константы «default», все эффекты и сложность по id.
static func from_registry(reg: ContentRegistry, difficulty_id: StringName = &"normal") -> PlayerVitals:
	var fx := {}
	for e in reg.get_entries("effects"):
		fx[StringName(e["id"])] = e
	var d := reg.get_entry("difficulties", difficulty_id) if reg.has_entry("difficulties", difficulty_id) else {}
	return PlayerVitals.new(reg.get_entry("survival", &"default"), fx, d)


func health_max() -> float:
	return _c("health_max", 100.0)


func stamina_max() -> float:
	return _c("stamina_max", 100.0)


func set_difficulty(d: Dictionary) -> void:
	diff = d


## События с прошлого вызова: { type: damage|effect_added|effect_removed|death|cured, ... }.
func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


# --- Тик ---------------------------------------------------------------------------------

## Шаг симуляции. dt — реальные секунды, hours — игровые часы за тот же шаг.
## env: ambient (°C воздуха), heat (°C от костров), in_water, head_in_water, sprinting,
## moving, jumped, working, sleeping, insulation, water_resist, rain (0..1), contact_damage,
## contact_cause.
func tick(dt: float, hours: float, env: Dictionary) -> void:
	if dead:
		return
	var sleeping: bool = env.get("sleeping", false)
	_tick_temperature(hours, env)
	_tick_wetness(dt, hours, env)
	_tick_food(dt, hours, env)
	_tick_stamina(dt, env)
	_tick_air(dt, env)
	_tick_effects(hours, sleeping)
	_tick_regen(hours)
	if sleeping:
		fatigue = maxf(0.0, fatigue - _c("sleep_fatigue_per_hour", 14.0) * float(env.get("rest", 1.0)) * hours)
	else:
		fatigue = minf(100.0, fatigue + _c("fatigue_per_hour", 4.0) * hours)
	var contact: float = env.get("contact_damage", 0.0)
	if contact > 0.0:
		damage(contact * dt, String(env.get("contact_cause", CAUSE_FIRE)))


## Ощущаемая температура: воздух + тепло + одежда + баффы − мокрость (+ движение).
func perceived_temperature(env: Dictionary) -> float:
	var ambient: float = env.get("ambient", 20.0)
	var p := ambient + float(env.get("heat", 0.0))
	var ins: float = env.get("insulation", 0.0)
	# Одежда греет в холоде и немного мешает в жару.
	p += ins if p < _c("comfort_high", 28.0) else ins * 0.25
	p += _effect_sum("warmth")
	p -= _c("wet_cold", 12.0) * wetness * (1.0 - clampf(float(env.get("water_resist", 0.0)), 0.0, 1.0))
	if env.get("sprinting", false) and env.get("moving", false):
		p += 3.0
	elif env.get("moving", false) or env.get("working", false):
		p += 1.0
	return p


func _tick_temperature(hours: float, env: Dictionary) -> void:
	perceived = perceived_temperature(env)
	var normal := _c("body_temp_normal", 37.0)
	if not temperature_enabled:
		body_temp = normal
		return
	var low := _c("comfort_low", 14.0)
	var high := _c("comfort_high", 28.0)
	var rate := _c("body_temp_rate", 0.35)
	if perceived < low:
		body_temp -= rate * (low - perceived) / 10.0 * hours
	elif perceived > high:
		body_temp += rate * (perceived - high) / 10.0 * hours
	else:
		body_temp = move_toward(body_temp, normal, _c("body_recover_rate", 1.2) * hours)
	body_temp = clampf(body_temp, 28.0, 44.0)
	# Жар от болезни: тело не остывает ниже нормы + сдвиг.
	var fever := _effect_sum("temp_shift")
	if fever > 0.0 and body_temp < normal + fever:
		body_temp = move_toward(body_temp, normal + fever, hours * 2.0)
	var hypo := _c("hypothermia", 35.0)
	if body_temp < hypo:
		damage(_c("cold_damage_per_hour", 10.0) * (hypo - body_temp + 0.5) * hours, CAUSE_COLD)
		if body_temp < _c("frostbite_temp", 33.5):
			add_effect(&"frostbite", true)
	var hot := _c("heatstroke", 39.3)
	if body_temp > hot and fever <= 0.0:
		damage(_c("heat_damage_per_hour", 8.0) * (body_temp - hot + 0.5) * hours, CAUSE_HEAT)
		add_effect(&"heatstroke", true)
	# Простуда и грипп: переохлаждение и мокрость в холоде.
	if diseases_enabled and not has_effect(&"cold") and not has_effect(&"flu"):
		var risk := clampf((normal - 0.4 - body_temp) / 1.6, 0.0, 1.0)
		if perceived < low:
			risk += wetness * 0.6
		var p_hour := _c("cold_chance_per_hour", 0.18) * risk * _d("disease_mult")
		if p_hour > 0.0 and rng.randf() < 1.0 - exp(-p_hour * hours):
			# Сильное переохлаждение — сразу грипп, иначе простуда.
			add_effect(&"flu" if body_temp < _c("hypothermia", 35.0) + 0.5 else &"cold", true)


func _tick_wetness(dt: float, hours: float, env: Dictionary) -> void:
	if env.get("in_water", false):
		wetness = minf(1.0, wetness + _c("wet_in_water_per_s", 0.5) * dt)
		return
	var rain: float = env.get("rain", 0.0)
	if rain > 0.0:
		wetness = minf(1.0, wetness + rain * 0.02 * dt * (1.0 - clampf(float(env.get("water_resist", 0.0)), 0.0, 1.0)))
		return
	var warm := 1.0 + maxf(0.0, perceived - 15.0) / 10.0
	wetness = maxf(0.0, wetness - _c("dry_per_hour", 0.8) * warm * hours)


func _tick_food(dt: float, hours: float, env: Dictionary) -> void:
	var sleeping: bool = env.get("sleeping", false)
	var h_rate := _c("hunger_per_hour", 3.5) * _d("hunger_mult") * _effect_mult("hunger_mult")
	var t_rate := _c("thirst_per_hour", 5.0) * _d("thirst_mult") * _effect_mult("thirst_mult")
	if env.get("sprinting", false) and env.get("moving", false):
		h_rate *= _c("sprint_hunger_mult", 2.0)
		t_rate *= 1.3
	if perceived < _c("comfort_low", 14.0):
		h_rate *= _c("cold_hunger_mult", 1.5)
	elif perceived > _c("comfort_high", 28.0):
		t_rate *= _c("heat_thirst_mult", 1.8)
	if sleeping:
		h_rate *= 0.5
		t_rate *= 0.5
	hunger = maxf(0.0, hunger - h_rate * hours)
	if env.get("working", false):
		hunger = maxf(0.0, hunger - _c("work_hunger", 0.12) * dt * _d("hunger_mult"))
	if thirst_enabled:
		thirst = maxf(0.0, thirst - t_rate * hours)
	else:
		thirst = 100.0
	if diff.get("starve", true):
		if hunger <= 0.0:
			damage(_c("starve_damage_per_hour", 15.0) * hours, CAUSE_STARVE)
		if thirst <= 0.0:
			damage(_c("dehydrate_damage_per_hour", 22.0) * hours, CAUSE_THIRST)


func _tick_stamina(dt: float, env: Dictionary) -> void:
	var spent := 0.0
	if env.get("sprinting", false) and env.get("moving", false):
		spent += _c("sprint_stamina_per_s", 12.0) * dt
	if env.get("working", false):
		spent += _c("work_stamina_per_s", 3.0) * dt
	if env.get("jumped", false):
		spent += _c("jump_stamina", 5.0)
	if spent > 0.0:
		stamina = maxf(0.0, stamina - spent)
		_stamina_delay = _c("stamina_regen_delay_s", 1.2)
		if stamina <= 0.0:
			exhausted = true
		return
	if _stamina_delay > 0.0:
		_stamina_delay -= dt
		return
	var mult := _effect_mult("stamina_regen_mult")
	if hunger < LOW_FOOD or thirst < LOW_FOOD:
		mult *= 0.5
	if fatigue >= _c("tired_fatigue", 75.0):
		mult *= 0.6
	stamina = minf(stamina_max(), stamina + _c("stamina_regen_per_s", 16.0) * mult * dt)
	if exhausted and stamina >= RECOVER_STAMINA:
		exhausted = false


func _tick_air(dt: float, env: Dictionary) -> void:
	var max_air := _c("air_max_s", 15.0)
	if env.get("head_in_water", false):
		air -= dt
		if air <= 0.0:
			air = 0.0
			damage(_c("drown_damage_per_s", 8.0) * dt, CAUSE_DROWN)
	else:
		air = minf(max_air, air + max_air * 0.5 * dt)


func _tick_regen(hours: float) -> void:
	if health >= health_max() or dead:
		return
	if hunger < _c("regen_min_hunger", 55.0) or thirst < _c("regen_min_thirst", 35.0):
		return
	if has_disease() or body_temp < _c("hypothermia", 35.0) or body_temp > _c("heatstroke", 39.3):
		return
	var r := _c("regen_per_hour", 8.0) * _d("regen_mult") * _effect_mult("regen_mult")
	health = minf(health_max(), health + r * hours)


func _tick_effects(hours: float, sleeping: bool) -> void:
	var hp := 0.0
	var cause := ""
	var i := 0
	while i < effects.size():
		var e: Dictionary = effects[i]
		var st := _stage(e)
		var hph: float = st.get("health_per_hour", 0.0)
		if hph != 0.0:
			hp += hph * hours
			if hph < 0.0:
				cause = String(e["id"])
		if float(e["left"]) < 0.0:
			i += 1
			continue
		var def: Dictionary = effect_defs.get(StringName(e["id"]), {})
		var speed := 2.0 if sleeping and def.get("bed_rest", false) else 1.0
		e["left"] = float(e["left"]) - hours * speed
		if float(e["left"]) > 0.0:
			i += 1
			continue
		if not _advance_effect(i):
			continue   # эффект снят — i уже указывает на следующий
		i += 1
	if hp > 0.0:
		health = minf(health_max(), health + hp)
	elif hp < 0.0:
		# Урон болезней не масштабируется сложностью повторно: он уже в данных.
		_hurt(-hp, cause)


## Стадия закончилась: ухудшение (следующая стадия или next_effect) или выздоровление.
## Возвращает false, если эффект снят с позиции i.
func _advance_effect(i: int) -> bool:
	var e: Dictionary = effects[i]
	var id := StringName(e["id"])
	var def: Dictionary = effect_defs.get(id, {})
	var stages: Array = def.get("stages", [])
	var worsen := rng.randf() < float(def.get("worsen_chance", 0.0))
	if worsen and int(e["stage"]) + 1 < stages.size():
		e["stage"] = int(e["stage"]) + 1
		e["left"] = _stage_hours(stages[e["stage"]])
		_events.append({ "type": "effect_stage", "id": id, "stage": e["stage"] })
		return true
	effects.remove_at(i)
	_events.append({ "type": "effect_removed", "id": id })
	var nxt := StringName(def.get("next_effect", ""))
	if worsen and nxt != &"" and int(e["stage"]) + 1 >= stages.size():
		add_effect(nxt, true)
	return false


# --- Эффекты -----------------------------------------------------------------------------

## Наложить эффект (если уже есть — обновить таймер стадии). random — болезнь «случилась»:
## тогда её отключают настройка «Болезни» и сложность с disease_mult = 0.
func add_effect(id: StringName, random: bool = false) -> bool:
	var def: Dictionary = effect_defs.get(id, {})
	if def.is_empty():
		return false
	if def.get("kind", "") == "disease" and random and (not diseases_enabled or _d("disease_mult") <= 0.0):
		return false
	for e in effects:
		if StringName(e["id"]) == id:
			var left := _stage_hours(_stage(e))
			if left > float(e["left"]):
				e["left"] = left
			return false
	var stages: Array = def.get("stages", [])
	if stages.is_empty():
		return false
	effects.append({ "id": id, "stage": 0, "left": _stage_hours(stages[0]) })
	_events.append({ "type": "effect_added", "id": id })
	return true


func remove_effect(id: StringName) -> bool:
	for i in effects.size():
		if StringName(effects[i]["id"]) == id:
			effects.remove_at(i)
			_events.append({ "type": "effect_removed", "id": id })
			return true
	return false


func has_effect(id: StringName) -> bool:
	for e in effects:
		if StringName(e["id"]) == id:
			return true
	return false


## Есть ли болезнь (kind = disease): мешает регенерации.
func has_disease() -> bool:
	for e in effects:
		if String(effect_defs.get(StringName(e["id"]), {}).get("kind", "")) == "disease":
			return true
	return false


## Текущая стадия эффекта (словарь из data/effects.json).
func stage_of(id: StringName) -> Dictionary:
	for e in effects:
		if StringName(e["id"]) == id:
			return _stage(e)
	return {}


func _stage(e: Dictionary) -> Dictionary:
	var stages: Array = effect_defs.get(StringName(e["id"]), {}).get("stages", [])
	if stages.is_empty():
		return {}
	return stages[clampi(int(e["stage"]), 0, stages.size() - 1)]


static func _stage_hours(st: Dictionary) -> float:
	var h: float = st.get("hours", 0.0)
	return h if h > 0.0 else -1.0


func _effect_mult(key: String) -> float:
	var m := 1.0
	for e in effects:
		m *= float(_stage(e).get(key, 1.0))
	return m


func _effect_sum(key: String) -> float:
	var s := 0.0
	for e in effects:
		s += float(_stage(e).get(key, 0.0))
	return s


# --- Действия ----------------------------------------------------------------------------

## Урон от окружения (падение, огонь, холод); масштабируется сложностью.
func damage(amount: float, cause: String) -> void:
	if amount <= 0.0 or dead:
		return
	_hurt(amount * _d("damage_mult"), cause)


func _hurt(amount: float, cause: String) -> void:
	if amount <= 0.0 or dead:
		return
	health = maxf(0.0, health - amount)
	_events.append({ "type": "damage", "amount": amount, "cause": cause })
	if health <= 0.0:
		dead = true
		death_cause = cause
		_events.append({ "type": "death", "cause": cause })


## Падение с высоты blocks: урон, перелом (с шансом) и рана при сильном ударе.
## Возвращает нанесённый урон до множителя сложности.
func fall(blocks: float) -> float:
	var safe := _c("fall_safe", 3.5)
	if blocks <= safe or dead:
		return 0.0
	var dmg := (blocks - safe) * _c("fall_damage_per_block", 7.0)
	damage(dmg, CAUSE_FALL)
	if dead:
		return dmg
	if blocks >= _c("fracture_min_fall", 7.0) and rng.randf() < _c("fracture_chance", 0.35) * _d("disease_mult"):
		add_effect(&"fracture", true)
	if dmg >= _c("wound_min_damage", 18.0):
		add_effect(&"wound")
	return dmg


## Съесть или выпить еду (поле food предмета). freshness 0..1 — свежесть (порча — этап 9).
func eat(food: Dictionary, freshness: float = 1.0) -> void:
	if dead or food.is_empty():
		return
	var spoiled := freshness < SPOILED
	var nutr: float = food.get("nutrition", 0.0)
	hunger = clampf(hunger + nutr * (0.5 if spoiled else 1.0), 0.0, 100.0)
	thirst = clampf(thirst + float(food.get("thirst", 0.0)), 0.0, 100.0)
	if food.get("hot", false):
		add_effect(&"warm_meal")
	for fx: Dictionary in food.get("effects", []):
		var id := StringName(fx.get("id", ""))
		var chance: float = fx.get("chance", 1.0)
		if String(effect_defs.get(id, {}).get("kind", "")) == "disease":
			chance *= _d("disease_mult")
		if rng.randf() < chance:
			add_effect(id, true)
	if spoiled and rng.randf() < _c("spoiled_poison_chance", 0.6) * _d("disease_mult"):
		add_effect(&"food_poisoning", true)


## Выпить воды: fresh — пресная, dirty — грязная, sea — морская, purified — очищенная.
func drink(kind: StringName) -> void:
	if dead:
		return
	match kind:
		&"sea":
			thirst = clampf(thirst + _c("sea_water_thirst", -6.0), 0.0, 100.0)
			return
		&"dirty":
			_drink_risk(_c("dirty_water_chance", 0.35))
		&"fresh":
			_drink_risk(_c("fresh_water_chance", 0.02))
	thirst = minf(100.0, thirst + _c("drink_amount", 25.0))


func _drink_risk(chance: float) -> void:
	if rng.randf() < chance * _d("disease_mult"):
		add_effect(&"dysentery", true)


## Применить лекарство (поле medicine): снять эффекты из cures (с шансом), подлечить,
## наложить applies. Возвращает список снятых эффектов.
func apply_medicine(med: Dictionary) -> Array[StringName]:
	var cured: Array[StringName] = []
	if dead or med.is_empty():
		return cured
	var chance: float = med.get("chance", 1.0)
	for c in med.get("cures", []):
		var id := StringName(c)
		if has_effect(id) and rng.randf() < chance:
			remove_effect(id)
			cured.append(id)
			_events.append({ "type": "cured", "id": id })
	var heal: float = med.get("heal", 0.0)
	if heal > 0.0:
		health = minf(health_max(), health + heal)
	for a in med.get("applies", []):
		# Шина накладывается только на перелом.
		if StringName(a) == &"splinted" and not cured.has(&"fracture"):
			continue
		add_effect(StringName(a))
	return cured


## Можно ли сейчас употребить: еда — если не сыт до отказа (горячее — и сытым, если замёрз),
## лекарство — если есть что лечить.
func wants(food: Dictionary, med: Dictionary) -> bool:
	if not med.is_empty():
		if float(med.get("heal", 0.0)) > 0.0 and health < health_max():
			return true
		for c in med.get("cures", []):
			if has_effect(StringName(c)):
				return true
		if food.is_empty():
			return false
	if food.is_empty():
		return false
	var nutr: float = food.get("nutrition", 0.0)
	var thr: float = food.get("thirst", 0.0)
	var chilled := body_temp < _c("body_temp_normal", 37.0) - 0.3 or perceived < _c("comfort_low", 14.0)
	return (nutr > 0.0 and hunger < 99.0) or (thr > 0.0 and thirst < 99.0) or (bool(food.get("hot", false)) and chilled)


## Сон: hours игровых часов в кровати с качеством rest. Голод и жажда идут вполовину,
## усталость снимается, болезни с bed_rest проходят вдвое быстрее. Сон прерывается,
## если стало опасно (здоровье ниже 25 % или игрок умер).
func sleep(hours: float, rest: float, env: Dictionary) -> float:
	var e := env.duplicate()
	e["sleeping"] = true
	e["rest"] = rest
	e["moving"] = false
	e["sprinting"] = false
	var slept := 0.0
	while slept < hours - 0.0001 and not dead:
		var step := minf(SLEEP_STEP_H, hours - slept)
		tick(step * 3600.0 / 60.0, step, e)
		slept += step
		if health < health_max() * 0.25:
			break
	if not dead and slept >= 4.0 and fatigue < 30.0:
		add_effect(&"rested")
	return slept


## Возрождение: полное здоровье, часть сытости, эффекты сняты.
func respawn() -> void:
	dead = false
	death_cause = ""
	health = health_max()
	stamina = stamina_max()
	hunger = _c("respawn_hunger", 70.0)
	thirst = _c("respawn_thirst", 70.0)
	body_temp = _c("body_temp_normal", 37.0)
	wetness = 0.0
	air = _c("air_max_s", 15.0)
	fatigue = 0.0
	exhausted = false
	effects.clear()


# --- Влияние на движение -----------------------------------------------------------------

## Множитель скорости: болезни и травмы (перелом), сильная усталость, голод.
func speed_mult() -> float:
	var m := _effect_mult("speed_mult")
	if fatigue >= 95.0:
		m *= 0.9
	if hunger <= 0.0 or thirst <= 0.0:
		m *= 0.85
	return m


## Можно ли бежать: выносливость, нет «хромоты», не умирает от голода.
func can_sprint() -> bool:
	if exhausted or stamina <= 0.0 or hunger <= 3.0:
		return false
	for e in effects:
		if _stage(e).get("no_sprint", false):
			return false
	return true


func is_tired() -> bool:
	return fatigue >= _c("tired_fatigue", 75.0)


# --- Сохранение --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var fx := []
	for e in effects:
		fx.append({ "id": String(e["id"]), "stage": int(e["stage"]), "left": float(e["left"]) })
	return {
		"health": health, "hunger": hunger, "thirst": thirst, "stamina": stamina,
		"body_temp": body_temp, "wetness": wetness, "air": air, "fatigue": fatigue,
		"effects": fx, "dead": dead,
	}


func from_dict(d: Dictionary) -> void:
	health = clampf(float(d.get("health", health_max())), 0.0, health_max())
	hunger = clampf(float(d.get("hunger", 100.0)), 0.0, 100.0)
	thirst = clampf(float(d.get("thirst", 100.0)), 0.0, 100.0)
	stamina = clampf(float(d.get("stamina", stamina_max())), 0.0, stamina_max())
	body_temp = clampf(float(d.get("body_temp", _c("body_temp_normal", 37.0))), 28.0, 44.0)
	wetness = clampf(float(d.get("wetness", 0.0)), 0.0, 1.0)
	air = clampf(float(d.get("air", _c("air_max_s", 15.0))), 0.0, _c("air_max_s", 15.0))
	fatigue = clampf(float(d.get("fatigue", 0.0)), 0.0, 100.0)
	dead = bool(d.get("dead", false))
	effects.clear()
	for e: Dictionary in d.get("effects", []):
		var id := StringName(e.get("id", ""))
		if effect_defs.has(id):
			effects.append({ "id": id, "stage": int(e.get("stage", 0)), "left": float(e.get("left", -1.0)) })


func _c(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


func _d(key: String) -> float:
	return float(diff.get(key, 1.0))
