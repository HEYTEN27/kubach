class_name DebugOverlay
extends CanvasLayer
## Отладочный экран F3 (раздел 20 ТЗ): FPS, frametime, очереди чанков, память, вызовы отрисовки,
## координаты, цель, режим. Биом, освещённость, температура тела и время.

const REFRESH_SEC := 0.25
const DIRS := ["север (−Z)", "северо-запад", "запад (−X)", "юго-запад", "юг (+Z)", "юго-восток", "восток (+X)", "северо-восток"]

var player: Player
var world: World
var world_name := ""
var survival: SurvivalController
var weather: WeatherSystem

var _label: Label
var _accum := 0.0
var _frame_min := INF
var _frame_max := 0.0
var _last_usec := 0


func _ready() -> void:
	layer = 20
	visible = false
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(8, 8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(_label)
	_last_usec = Time.get_ticks_usec()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		visible = not visible


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_frame_min = minf(_frame_min, frame_ms)
	_frame_max = maxf(_frame_max, frame_ms)
	_accum += delta
	if not visible or (_accum < REFRESH_SEC and _label.text != "") or player == null:
		return
	_accum = 0.0
	_label.text = build_text()
	_frame_min = INF
	_frame_max = 0.0


func build_text() -> String:
	var b := player.body
	var bx := floori(b.x)
	var by := floori(b.y)
	var bz := floori(b.z)
	var ch := world.chunks
	var dir_idx := posmod(roundi(player.yaw / (PI / 4.0)), 8)
	var lines := PackedStringArray()
	lines.append("%s %s · Godot %s" % [ProjectSettings.get_setting("application/config/name"),
		ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]])
	lines.append("FPS %d · кадр %.1f мс (мин %.1f / макс %.1f)" % [Engine.get_frames_per_second(),
		1000.0 / maxf(1.0, Engine.get_frames_per_second()), _frame_min, _frame_max])
	lines.append("XYZ: %.3f / %.3f / %.3f" % [b.x, b.y, b.z])
	lines.append("Блок: %d %d %d · колонна %d %d · секция %d (Y %d…%d)" % [bx, by, bz, bx >> 4, bz >> 4,
		WorldConst.section_index(by), WorldConst.section_base_y(maxi(0, WorldConst.section_index(by))),
		WorldConst.section_base_y(maxi(0, WorldConst.section_index(by))) + 15])
	lines.append("Взгляд: %s · рыскание %.1f° · тангаж %.1f°" % [DIRS[dir_idx], rad_to_deg(player.yaw), rad_to_deg(player.pitch)])
	lines.append("Origin: %d %d %d · сцена: %.2f %.2f %.2f" % [world.origin.x, world.origin.y, world.origin.z,
		player.position.x, player.position.y, player.position.z])
	lines.append("Чанки: колонн %d · генерация %d · мешинг %d · мешей %d · граней %d · применение %.2f мс" % [
		ch.columns.size(), ch.pending_generation(), ch.pending_meshing(), ch.mesh_node_count(), ch.stat_quads, ch.stat_last_apply_ms])
	lines.append("Дальность: %d колонн · пещеры в радиусе %d · потоков %d · мешер %s" % [
		ch.view_distance, ch.underground_radius, OS.get_processor_count(), ch.mesher_name()])
	lines.append("Память: %.0f МБ · видео %.0f МБ" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	lines.append("Отрисовка: вызовов %d · примитивов %d · объектов %d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	var m := player.motor
	lines.append("Режим: %s · полёт %s · присед %s · на земле %s · в воде %s" % [
		"творческий" if world.game_mode == &"creative" else "выживание", _yn(m.flying), _yn(m.crouching),
		_yn(b.on_ground), _yn(m.in_fluid)])
	var t: Dictionary = player.interaction.target
	if t.get("hit", false):
		var p: Vector3i = t["block"]
		var def := world.registry.block_by_num(world.get_block(p.x, p.y, p.z))
		lines.append("Цель: %s (%s) · %d %d %d · грань %s" % [def.display_name(), def.id, p.x, p.y, p.z, t["normal"]])
	else:
		lines.append("Цель: —")
	var bi := world.biome_at(bx, bz)
	if bi >= 0:
		var bsrc := world.generator.biomes
		var prov := world.generator.geology.province_at(bx, bz)
		lines.append("Биом: %s (%s) · %.0f °C · провинция: %s" % [
			bsrc.defs[bi]["name"]["ru"], bsrc.ids[bi], bsrc.temperature_c[bi], world.generator.geology.ids[prov]])
	else:
		lines.append("Биом: —")
	var light := ch.light_at(bx, by + 1, bz)
	if light.is_empty():
		lines.append("Свет: — · расчёт %s" % ch.light_name())
	else:
		lines.append("Свет: небо %d · блоки %d/%d/%d · расчёт %s · в очереди %d" % [
			light[0], light[1], light[2], light[3], ch.light_name(), ch.pending_lighting()])
	if survival != null:
		var v := survival.vitals
		var e := survival.env
		lines.append("Тело %.2f °C · ощущается %.1f · воздух %.1f · тепло %.1f · мокрость %.2f · усталость %.0f" % [
			v.body_temp, v.perceived, float(e.get("ambient", 0.0)), float(e.get("heat", 0.0)), v.wetness, v.fatigue])
		lines.append("Время %s · день %d · %s · дневной свет %.2f · сложность %s" % [survival.clock.time_text(),
			survival.clock.day, survival.clock.season(), survival.daylight, survival.difficulty])
	if weather != null:
		var w := weather.values
		var win := weather.clock.day_window()
		lines.append("Погода %s → %s (%.0f%%, ещё %.1f ч) · облака %.2f · дождь %.2f · снег %.2f · ветер %.2f · мокрость %.2f" % [
			weather.sim.previous, weather.sim.current, weather.sim.blend() * 100.0, weather.sim.left_hours,
			float(w.get("cloud", 0.0)), float(w.get("rain", 0.0)), float(w.get("snow", 0.0)), float(w.get("wind", 0.0)),
			weather.wetness])
		lines.append("Небо: восход %.2f · закат %.2f · луна %.2f · воздух снаружи %.1f °C · огней %d · громоотводов %d · молний %d" % [
			win.x, win.y, SkyMath.moon_phase(weather.clock.day, weather.clock.minute, weather.moon_cycle_days),
			weather.temperature, weather.fire.fires.size(), weather.rods.size(), weather.strikes])
	lines.append("Мир: %s · сид %d" % [world_name, world.world_seed])
	return "\n".join(lines)


func _yn(v: bool) -> String:
	return "да" if v else "нет"
