extends GutTest
## PlayerVitals: голод, жажда, температура тела, мокрость, выносливость, воздух, болезни,
## еда, вода, лекарства, сон, падение, смерть и возрождение (раздел 4.3 ТЗ).

var v: PlayerVitals

const COMFY := { "ambient": 20.0 }


func before_each() -> void:
	v = PlayerVitals.from_registry(Registry, &"normal")
	v.rng.seed = 12345


func _hours(h: float, env: Dictionary = COMFY, step: float = 0.1) -> void:
	var t := 0.0
	while t < h - 0.0001:
		var s := minf(step, h - t)
		v.tick(s * 60.0, s, env)
		t += s


func test_data_loaded() -> void:
	assert_true(Registry.has_entry("survival", &"default"))
	assert_eq(v.health, 100.0)
	assert_almost_eq(v.body_temp, 37.0, 0.001)
	assert_false(v.effect_defs.is_empty())


func test_hunger_and_thirst_drop_over_time() -> void:
	v.diseases_enabled = false
	_hours(10.0)
	assert_almost_eq(v.hunger, 100.0 - 3.5 * 10.0, 0.5)
	assert_almost_eq(v.thirst, 100.0 - 5.0 * 10.0, 0.5)


func test_sprint_and_cold_burn_more_food() -> void:
	v.diseases_enabled = false
	v.temperature_enabled = false
	_hours(4.0, { "ambient": 20.0, "sprinting": true, "moving": true })
	var sprint_hunger := 100.0 - v.hunger
	v = PlayerVitals.from_registry(Registry, &"normal")
	v.diseases_enabled = false
	v.temperature_enabled = false
	_hours(4.0, { "ambient": -10.0 })
	var cold_hunger := 100.0 - v.hunger
	assert_almost_eq(sprint_hunger, 3.5 * 4.0 * 2.0, 0.5, "бег — вдвое")
	assert_almost_eq(cold_hunger, 3.5 * 4.0 * 1.5, 0.5, "холод — в полтора раза")


func test_heat_drains_thirst_faster() -> void:
	v.diseases_enabled = false
	v.temperature_enabled = false
	_hours(4.0, { "ambient": 38.0 })
	assert_almost_eq(100.0 - v.thirst, 5.0 * 4.0 * 1.8, 0.5)


func test_difficulty_scales_hunger() -> void:
	v = PlayerVitals.from_registry(Registry, &"peaceful")
	_hours(10.0)
	assert_almost_eq(v.hunger, 100.0 - 3.5 * 10.0 * 0.5, 0.5)


func test_starvation_damages_and_kills() -> void:
	v.hunger = 0.0
	v.thirst = 100.0
	_hours(1.0)
	assert_lt(v.health, 100.0)
	_hours(10.0)
	assert_true(v.dead)
	assert_eq(v.death_cause, PlayerVitals.CAUSE_STARVE)
	var events := v.take_events()
	assert_eq(events.back()["type"], "death")


func test_peaceful_does_not_starve() -> void:
	v = PlayerVitals.from_registry(Registry, &"peaceful")
	v.hunger = 0.0
	v.thirst = 0.0
	v.health = 50.0
	_hours(3.0)
	assert_eq(v.health, 50.0, "на мирной голод не убивает (и не лечит)")


func test_regen_only_when_fed_and_healthy() -> void:
	v.diseases_enabled = false
	v.health = 50.0
	_hours(2.0)
	assert_almost_eq(v.health, 50.0 + 8.0 * 2.0, 0.5)
	v.hunger = 20.0
	var h := v.health
	_hours(1.0)
	assert_almost_eq(v.health, h, 0.01, "голодный не лечится")
	v.hunger = 100.0
	v.add_effect(&"cold")
	h = v.health
	_hours(0.5)
	assert_almost_eq(v.health, h, 0.01, "больной не лечится")


func test_body_temperature_drops_in_cold_and_recovers() -> void:
	v.diseases_enabled = false
	_hours(1.0, { "ambient": -20.0 })
	assert_lt(v.body_temp, 36.0)
	_hours(3.0, { "ambient": 20.0 })
	assert_almost_eq(v.body_temp, 37.0, 0.01)


func test_clothing_and_fire_keep_warm() -> void:
	v.diseases_enabled = false
	_hours(1.0, { "ambient": 0.0, "insulation": 15.0 })
	assert_almost_eq(v.body_temp, 37.0, 0.01, "тёплая одежда — комфорт")
	_hours(1.0, { "ambient": 0.0, "heat": 16.0 })
	assert_almost_eq(v.body_temp, 37.0, 0.01, "у костра — комфорт")


func test_hypothermia_hurts_and_causes_frostbite() -> void:
	v.diseases_enabled = true
	_hours(4.0, { "ambient": -30.0 })
	assert_lt(v.body_temp, 35.0)
	assert_lt(v.health, 100.0)
	assert_true(v.has_effect(&"frostbite"))


func test_heatstroke() -> void:
	_hours(12.0, { "ambient": 48.0 })
	assert_gt(v.body_temp, 39.3)
	assert_true(v.has_effect(&"heatstroke"))


func test_wetness_and_cold() -> void:
	v.diseases_enabled = false
	v.tick(3.0, 0.05, { "ambient": 20.0, "in_water": true })
	assert_almost_eq(v.wetness, 1.0, 0.001)
	var dry := v.perceived_temperature({ "ambient": 10.0 })
	assert_almost_eq(dry, 10.0 - 12.0, 0.01, "мокрый мёрзнет")
	assert_almost_eq(v.perceived_temperature({ "ambient": 10.0, "water_resist": 1.0 }), 10.0, 0.01, "непромокаемая одежда")
	_hours(2.0, { "ambient": 20.0 })
	assert_eq(v.wetness, 0.0, "высох")


func test_wet_and_cold_catches_cold() -> void:
	var got := false
	for i in 10:
		v = PlayerVitals.from_registry(Registry, &"normal")
		v.rng.seed = i
		v.wetness = 1.0
		_hours(6.0, { "ambient": 2.0, "in_water": false, "rain": 1.0 })
		if v.has_effect(&"cold") or v.has_effect(&"flu"):
			got = true
			break
	assert_true(got, "мокрым в холоде — простуда")


func test_disease_setting_off() -> void:
	v.diseases_enabled = false
	assert_false(v.add_effect(&"cold", true))
	assert_true(v.add_effect(&"cold", false), "явно наложенный эффект проходит")


func test_stamina_sprint_jump_and_regen() -> void:
	v.tick(1.0, 0.0, { "sprinting": true, "moving": true })
	assert_almost_eq(v.stamina, 88.0, 0.01)
	v.tick(0.05, 0.0, { "jumped": true })
	assert_almost_eq(v.stamina, 83.0, 0.01)
	v.tick(0.5, 0.0, {})
	assert_almost_eq(v.stamina, 83.0, 0.01, "задержка перед восстановлением")
	v.tick(0.8, 0.0, {})
	v.tick(1.0, 0.0, {})
	assert_gt(v.stamina, 95.0)


func test_exhaustion_blocks_sprint_until_recovered() -> void:
	for i in 10:
		v.tick(1.0, 0.0, { "sprinting": true, "moving": true })
	assert_eq(v.stamina, 0.0)
	assert_false(v.can_sprint())
	v.tick(2.0, 0.0, {})
	assert_false(v.can_sprint(), "пока меньше 25")
	v.tick(2.0, 0.0, {})
	assert_true(v.can_sprint())


func test_drowning() -> void:
	v.tick(10.0, 0.0, { "head_in_water": true })
	assert_almost_eq(v.air, 5.0, 0.01)
	assert_eq(v.health, 100.0)
	v.tick(10.0, 0.0, { "head_in_water": true })
	assert_eq(v.air, 0.0)
	assert_lt(v.health, 100.0)
	v.tick(2.0, 0.0, {})
	assert_eq(v.air, 15.0, "вынырнул — отдышался")


func test_fall_damage_fracture_and_wound() -> void:
	assert_eq(v.fall(3.0), 0.0, "до 3,5 блока без урона")
	assert_almost_eq(v.fall(5.5), 14.0, 0.01)
	assert_almost_eq(v.health, 86.0, 0.01)
	v.health = 100.0
	var fractures := 0
	for i in 40:
		var t := PlayerVitals.from_registry(Registry, &"normal")
		t.rng.seed = i
		t.fall(8.0)
		if t.has_effect(&"fracture"):
			fractures += 1
		assert_true(t.has_effect(&"wound"), "сильный удар — рана")
	assert_between(fractures, 5, 25, "перелом с шансом ~35%")


func test_fracture_slows_and_splint_replaces_it() -> void:
	v.add_effect(&"fracture")
	assert_false(v.can_sprint())
	assert_lt(v.speed_mult(), 1.0)
	var cured := v.apply_medicine(Registry.item(&"splint").medicine)
	assert_eq(cured, [&"fracture"] as Array[StringName])
	assert_false(v.has_effect(&"fracture"))
	assert_true(v.has_effect(&"splinted"))
	for i in 49:
		v.hunger = 100.0
		v.thirst = 100.0
		v.tick(60.0, 1.0, COMFY)
	assert_false(v.dead)
	assert_false(v.has_effect(&"splinted"), "срослось за двое суток")


func test_splint_without_fracture_does_nothing() -> void:
	v.apply_medicine(Registry.item(&"splint").medicine)
	assert_false(v.has_effect(&"splinted"))


func test_untreated_wound_becomes_infected() -> void:
	v.add_effect(&"wound")
	_hours(6.5, COMFY, 0.5)
	assert_false(v.has_effect(&"wound"))
	assert_true(v.has_effect(&"wound_infection"))


func test_bandage_cures_wound() -> void:
	v.add_effect(&"wound")
	v.apply_medicine(Registry.item(&"bandage").medicine)
	assert_false(v.has_effect(&"wound"))


func test_eat_food() -> void:
	v.hunger = 40.0
	v.thirst = 40.0
	v.eat(Registry.item(&"mushroom_soup").food)
	assert_gt(v.hunger, 40.0)
	assert_gt(v.thirst, 40.0, "суп немного поит")
	assert_true(v.has_effect(&"warm_meal"), "горячая еда согревает")
	var p := v.perceived_temperature({ "ambient": 0.0 })
	assert_almost_eq(p, 8.0, 0.01)


func test_raw_meat_can_poison() -> void:
	var poisoned := 0
	for i in 40:
		var t := PlayerVitals.from_registry(Registry, &"normal")
		t.rng.seed = i
		t.eat(Registry.item(&"raw_meat").food)
		if t.has_effect(&"food_poisoning"):
			poisoned += 1
	assert_between(poisoned, 1, 39)
	var safe := PlayerVitals.from_registry(Registry, &"peaceful")
	for i in 20:
		safe.eat(Registry.item(&"raw_meat").food)
	assert_false(safe.has_effect(&"food_poisoning"), "на мирной болезней нет")


func test_spoiled_food_poisons() -> void:
	var poisoned := 0
	for i in 30:
		var t := PlayerVitals.from_registry(Registry, &"normal")
		t.rng.seed = i
		t.eat(Registry.item(&"cooked_meat").food, 0.1)
		if t.has_effect(&"food_poisoning"):
			poisoned += 1
	assert_gt(poisoned, 8)


func test_water_kinds() -> void:
	v.thirst = 50.0
	v.drink(&"purified")
	assert_eq(v.thirst, 75.0)
	v.drink(&"sea")
	assert_eq(v.thirst, 69.0, "морская вода сушит")
	var sick := 0
	for i in 40:
		var t := PlayerVitals.from_registry(Registry, &"normal")
		t.rng.seed = i
		t.drink(&"dirty")
		if t.has_effect(&"dysentery"):
			sick += 1
	assert_between(sick, 4, 28, "грязная вода — дизентерия ~35%")


func test_wants() -> void:
	var soup: Dictionary = Registry.item(&"mushroom_soup").food
	v.hunger = 100.0
	v.thirst = 100.0
	assert_false(v.wants(soup, {}), "сыт и не замёрз")
	v.body_temp = 36.0
	assert_true(v.wants(soup, {}), "горячее можно и сытым, если замёрз")
	v.body_temp = 37.0
	var meat: Dictionary = Registry.item(&"cooked_meat").food
	assert_false(v.wants(meat, {}))
	v.hunger = 50.0
	assert_true(v.wants(meat, {}))
	var bandage: Dictionary = Registry.item(&"bandage").medicine
	assert_false(v.wants({}, bandage))
	v.add_effect(&"wound")
	assert_true(v.wants({}, bandage))


func test_sleep_restores_fatigue_and_speeds_recovery() -> void:
	v.diseases_enabled = false
	v.fatigue = 90.0
	assert_true(v.is_tired())
	v.add_effect(&"cold")
	var slept := v.sleep(8.0, 1.0, COMFY)
	assert_almost_eq(slept, 8.0, 0.01)
	assert_lt(v.fatigue, 1.0)
	assert_true(v.has_effect(&"rested"))
	assert_gt(v.hunger, 100.0 - 3.5 * 8.0, "во сне голод вполовину")


func test_contact_damage() -> void:
	v.tick(1.0, 0.0, { "contact_damage": 40.0, "contact_cause": "fire" })
	assert_almost_eq(v.health, 60.0, 0.01)


func test_respawn_and_save_roundtrip() -> void:
	v.add_effect(&"fracture")
	v.hunger = 33.0
	v.wetness = 0.5
	var d := v.to_dict()
	var w := PlayerVitals.from_registry(Registry, &"normal")
	w.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_almost_eq(w.hunger, 33.0, 0.001)
	assert_almost_eq(w.wetness, 0.5, 0.001)
	assert_true(w.has_effect(&"fracture"))
	w.damage(500.0, "fall")
	assert_true(w.dead)
	w.respawn()
	assert_false(w.dead)
	assert_eq(w.health, 100.0)
	assert_eq(w.hunger, 70.0)
	assert_true(w.effects.is_empty())
