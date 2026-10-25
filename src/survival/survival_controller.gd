class_name SurvivalController
extends Node
## Выживание в игре (этап 5): ведёт игровые часы, раз в 0,25 с опрашивает окружение
## (EnvironmentProbe), каждый кадр двигает PlayerVitals и переносит результат на игрока
## (скорость, запрет бега). Еда и лекарства — удержанием ПКМ с предметом в руке, вода —
## ПКМ пустой рукой по воде, сон — ПКМ по кровати, урон от падения — EventBus.player_landed.
## В творческом режиме параметры заморожены, время идёт.

## Игрок умер (причина — PlayerVitals.CAUSE_*, id эффекта или "contact").
signal died(cause: String)
## Эффект появился или прошёл — для подсказок HUD.
signal effect_changed(id: StringName, added: bool)
## Получен урон (для красной вспышки HUD).
signal hurt(amount: float, cause: String)
## Короткое сообщение игроку.
signal message(text: String)

const PROBE_INTERVAL := 0.25
const DRINK_SECONDS := 1.0
const DRINK_REACH := 4.0
## Сон в кровати: одеяло греет как одежда.
const BED_INSULATION := 8.0

var world: World
var player: Player
var vitals: PlayerVitals
var clock: GameClock
var probe: EnvironmentProbe
var difficulty: StringName = &"normal"
## Точка возрождения: { x, y, z, bed } (bed — координаты кровати или пусто).
var spawn := {}
## Последний опрос окружения (для HUD и экрана состояния).
var env := {}
## Прогресс еды/питья 0..1 и что едим (id предмета или &"water").
var consume_progress := 0.0
var consume_what: StringName = &""
## Дневной свет 0..1 (выставляет игра по GraphicsRig, для F3).
var daylight := 1.0
## Идёт ли время: игра выставляет после загрузки мира (во время загрузки часы стоят).
var running := false

var _probe_left := 0.0
var _consume_slot := -1


func setup(p_world: World, p_player: Player, day_length_min: float) -> void:
	world = p_world
	player = p_player
	clock = GameClock.new(day_length_min)
	clock.start_season = maxi(0, world.settings.season_index())
	clock.season_length = world.settings.season_length
	vitals = PlayerVitals.from_registry(world.registry, difficulty)
	probe = EnvironmentProbe.new(world, vitals.cfg)
	EventBus.player_landed.connect(_on_landed)


func set_difficulty(id: StringName) -> void:
	if not world.registry.has_entry("difficulties", id):
		return
	difficulty = id
	vitals.set_difficulty(world.registry.get_entry("difficulties", id))


func difficulty_def() -> Dictionary:
	return vitals.diff


func is_active() -> bool:
	return world.game_mode != &"creative"


func _process(delta: float) -> void:
	if not running or (not player.active and not vitals.dead):
		return
	var hours := clock.advance(delta)
	if vitals.dead:
		return
	_probe_left -= delta
	if _probe_left <= 0.0:
		_probe_left = PROBE_INTERVAL
		var eye := player.eye_world()
		env = probe.sample(player.body.x, player.body.y, player.body.z, eye[1], clock)
	var jumped := player.jumps > 0
	player.jumps = 0
	if not is_active():
		player.survival_speed = 1.0
		player.can_sprint = true
		consume_progress = 0.0
		return
	var moving := Vector2(player.motor.vx, player.motor.vz).length() > 0.5
	var e := env.duplicate()
	e["sprinting"] = player.motor.sprinting
	e["moving"] = moving
	e["jumped"] = jumped
	e["working"] = player.interaction.break_progress > 0.0
	e["insulation"] = player.inventory.insulation_total()
	e["water_resist"] = player.inventory.water_resist_total()
	vitals.tick(delta, hours, e)
	_update_consume(delta)
	player.survival_speed = vitals.speed_mult()
	player.can_sprint = vitals.can_sprint()
	_dispatch_events()


func _dispatch_events() -> void:
	for ev in vitals.take_events():
		match String(ev["type"]):
			"damage":
				hurt.emit(float(ev["amount"]), String(ev["cause"]))
				if float(ev["amount"]) >= 1.0:
					Audio.play_ui("player/hurt")
			"death":
				Audio.play_ui("player/death")
				player.active = false
				consume_progress = 0.0
				died.emit(String(ev["cause"]))
			"effect_added":
				effect_changed.emit(StringName(ev["id"]), true)
			"effect_removed":
				effect_changed.emit(StringName(ev["id"]), false)


# --- Еда, лекарства, вода --------------------------------------------------------------

## Удержание ПКМ: предмет-еда в руке (блок-растение — только если прицел не на блоке)
## или пустая рука, смотрящая на воду.
func _update_consume(delta: float) -> void:
	var want := player.input_allowed() and Input.is_action_pressed(&"use")
	var what: StringName = &""
	var seconds := 1.0
	if want:
		var d := player.inventory.held_def()
		var aiming: bool = player.interaction.target.get("hit", false)
		if d != null and d.is_consumable() and (not d.is_block() or not aiming):
			if vitals.wants(d.food, d.medicine):
				what = d.id
				seconds = float(d.food.get("eat_seconds", 1.4)) if d.is_food() else 1.2
		elif d == null and _water_target() != &"":
			what = &"water"
			seconds = DRINK_SECONDS
	if what == &"" or what != consume_what or (what != &"water" and _consume_slot != player.inventory.selected):
		consume_progress = 0.0
		consume_what = what
		_consume_slot = player.inventory.selected
		if what == &"":
			return
	var before := consume_progress
	consume_progress += delta / seconds
	if floori(before * 3.0) != floori(consume_progress * 3.0):
		player.swing()
	if consume_progress < 1.0:
		return
	consume_progress = 0.0
	if what == &"water":
		var kind := _water_target()
		vitals.drink(kind)
		Audio.play_ui("player/drink")
		if kind == &"sea":
			message.emit("Морская вода — от неё только сильнее хочется пить")
		return
	var d := player.inventory.held_def()
	var s := player.inventory.held()
	if d == null or s == null:
		return
	if d.is_food():
		vitals.eat(d.food, float(s.data.get("freshness", 1.0)), String(s.data.get("cook", "")))
	if d.is_medicine():
		vitals.apply_medicine(d.medicine)
	Audio.play_ui("player/drink" if d.is_food() and float(d.food.get("nutrition", 0.0)) <= 0.0 else "player/eat")
	player.inventory.consume_held()


## Вид воды, на которую смотрит игрок: fresh, dirty, sea или пусто.
func _water_target() -> StringName:
	var eye := player.eye_world()
	var reg := world.registry
	var hit := VoxelRaycast.cast(eye[0], eye[1], eye[2], player.look_dir(), DRINK_REACH,
		func(x: int, y: int, z: int) -> bool:
			var b := world.get_block(x, y, z)
			return b > 0 and reg.block_render[b] != BlockDef.RENDER_INVISIBLE)
	if not hit["hit"]:
		return &""
	var p: Vector3i = hit["block"]
	var b := world.get_block(p.x, p.y, p.z)
	if reg.block_render[b] != BlockDef.RENDER_LIQUID or reg.block_heat[b] > 0.0:
		return &""
	return water_kind_at(p.x, p.z)


func water_kind_at(x: int, z: int) -> StringName:
	var bi := world.biome_at(x, z)
	if bi < 0 or bi >= world.generator.biomes.count:
		return &"fresh"
	return StringName(world.generator.biomes.defs[bi].get("water_kind", "fresh"))


# --- Падение, сон, смерть ---------------------------------------------------------------

func _on_landed(fall: float) -> void:
	if is_active() and not vitals.dead:
		vitals.fall(fall)
		_dispatch_events()


## ПКМ по кровати: точка возрождения; ночью — сон до утра, днём — если устал.
## Возвращает текст для подсказки.
func use_bed(pos: Vector3i) -> String:
	var def := world.registry.block_by_num(world.get_block(pos.x, pos.y, pos.z))
	if def == null or not def.is_bed():
		return ""
	var msg := ""
	if spawn.get("bed", []) != [pos.x, pos.y, pos.z]:
		spawn = { "x": pos.x + 0.5, "y": pos.y + 1.0, "z": pos.z + 0.5, "bed": [pos.x, pos.y, pos.z] }
		msg = "Точка возрождения — у этой кровати. "
	if not is_active():
		return msg
	var hours := 0.0
	if clock.is_night():
		hours = clock.hours_until(GameClock.NIGHT_END)
	elif vitals.is_tired():
		hours = minf(8.0, vitals.fatigue / maxf(1.0, float(vitals.cfg.get("sleep_fatigue_per_hour", 14.0)) * float(def.bed.get("rest", 1.0))))
	else:
		return msg + "Спать не хочется"
	var e := env.duplicate()
	e["insulation"] = player.inventory.insulation_total() + BED_INSULATION
	e["water_resist"] = player.inventory.water_resist_total()
	var slept := vitals.sleep(hours, float(def.bed.get("rest", 1.0)), e)
	clock.advance_hours(slept)
	_dispatch_events()
	Audio.play_ui("player/sleep")
	if vitals.dead:
		return ""
	if slept < hours - 0.01:
		return msg + "Сон прерван: вам плохо (%.1f ч)" % slept
	return msg + "Вы проспали %.1f ч. %s, день %d" % [slept, clock.time_text(), clock.day]


## Позиция возрождения: у кровати, если она цела и над ней свободно, иначе — точка мира.
func respawn_point(world_spawn: Array) -> Array:
	var bed: Array = spawn.get("bed", [])
	if bed.size() == 3:
		var b := world.get_block(int(bed[0]), int(bed[1]), int(bed[2]))
		var def := world.registry.block_by_num(b) if b > 0 else null
		var x := int(bed[0])
		var y := int(bed[1])
		var z := int(bed[2])
		if def != null and def.is_bed() and not world.is_solid(x, y + 1, z) and not world.is_solid(x, y + 2, z):
			return [x + 0.5, y + 1.0, z + 0.5]
		if b >= 0:
			spawn.erase("bed")   # кровать сломана — точка мира
	return world_spawn


func respawn() -> void:
	vitals.respawn()
	consume_progress = 0.0
	_probe_left = 0.0
	player.survival_speed = 1.0
	player.can_sprint = true


func to_dict() -> Dictionary:
	return { "vitals": vitals.to_dict(), "clock": clock.to_dict(), "spawn": spawn }


func from_dict(d: Dictionary) -> void:
	vitals.from_dict(d.get("vitals", {}))
	clock.from_dict(d.get("clock", {}))
	spawn = d.get("spawn", {})
	var bed: Array = spawn.get("bed", [])
	if bed.size() == 3:
		spawn["bed"] = [int(bed[0]), int(bed[1]), int(bed[2])]
