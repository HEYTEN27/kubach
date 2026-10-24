class_name SurvivalHud
extends Control
## Выживание на HUD (раздел 4.3): здоровье, выносливость, голод, жажда над хотбаром, пузыри
## воздуха под водой, температура тела и ощущаемая, мокрость, значки болезней и баффов с
## таймером, часы и день, кольцо еды/питья у прицела, виньетки урона, холода и жары.
## Рисуется в _draw без узлов на каждый элемент — дёшево.

const BAR_W := 230.0
const BAR_H := 10.0
const BADGE := 34.0

const C_HEALTH := Color(0.82, 0.2, 0.18)
const C_STAMINA := Color(0.9, 0.78, 0.3)
const C_HUNGER := Color(0.85, 0.55, 0.22)
const C_THIRST := Color(0.3, 0.6, 0.92)
const C_AIR := Color(0.7, 0.88, 1.0)

var survival: SurvivalController
var hotbar_width := 512.0
var _hurt_flash := 0.0
var _shown_stamina := 100.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func flash_hurt(amount: float) -> void:
	_hurt_flash = clampf(_hurt_flash + amount / 25.0, 0.0, 1.0)


func _process(delta: float) -> void:
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 1.5)
	if survival != null:
		_shown_stamina = lerpf(_shown_stamina, survival.vitals.stamina, clampf(delta * 10.0, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	if survival == null:
		return
	var v := survival.vitals
	var font := get_theme_default_font()
	var vs := size
	_draw_vignettes(v, vs)
	_draw_clock(font, vs)
	if not survival.is_active():
		return
	# Полоски над хотбаром: слева здоровье и выносливость, справа голод и жажда.
	var base_y := vs.y - 62.0 - 10.0 - 14.0
	var left := vs.x * 0.5 - hotbar_width * 0.5
	var right := vs.x * 0.5 + hotbar_width * 0.5 - BAR_W
	_bar(Vector2(left, base_y - 22.0), v.health / v.health_max(), C_HEALTH, "♥ %d" % ceili(v.health), font)
	_bar(Vector2(left, base_y), _shown_stamina / v.stamina_max(), C_STAMINA.darkened(0.35) if v.exhausted else C_STAMINA, "", font)
	_bar(Vector2(right, base_y - 22.0), v.hunger / 100.0, C_HUNGER, "Сытость %d" % roundi(v.hunger), font)
	if v.thirst_enabled:
		_bar(Vector2(right, base_y), v.thirst / 100.0, C_THIRST, "Вода %d" % roundi(v.thirst), font)
	# Воздух — пузыри над полосками, только под водой или пока не восстановился.
	var max_air := float(v.cfg.get("air_max_s", 15.0))
	if v.air < max_air - 0.01:
		var n := 10
		var full := ceili(v.air / max_air * n)
		for i in n:
			var c := Vector2(right + BAR_W - 9.0 - i * 18.0, base_y - 42.0)
			draw_circle(c, 7.0, Color(0, 0, 0, 0.4))
			if i < full:
				draw_circle(c, 5.5, C_AIR)
				draw_circle(c + Vector2(-2, -2), 1.6, Color(1, 1, 1, 0.8))
	# Температура тела и окружения, мокрость — справа снизу.
	if v.temperature_enabled:
		var bt := v.body_temp
		var col := Color(0.9, 0.9, 0.9)
		if bt < float(v.cfg.get("hypothermia", 35.0)) + 1.0:
			col = Color(0.55, 0.75, 1.0)
		elif bt > float(v.cfg.get("heatstroke", 39.3)) - 1.0:
			col = Color(1.0, 0.6, 0.3)
		var t := "Тело %s · ощущается %s" % [temp_text(bt, 1), temp_text(v.perceived, 0, true)]
		if v.wetness > 0.05:
			t += " · мокрый %d%%" % roundi(v.wetness * 100.0)
		_text(font, Vector2(vs.x - 16.0, vs.y - 64.0), t, 15, col, HORIZONTAL_ALIGNMENT_RIGHT)
	# Еда/питьё — кольцо вокруг прицела.
	if survival.consume_progress > 0.0:
		var c := vs * 0.5
		draw_arc(c, 18.0, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 5.0)
		draw_arc(c, 18.0, -PI * 0.5, -PI * 0.5 + TAU * survival.consume_progress, 40, Color(1, 1, 1, 0.9), 3.0)
	_draw_effects(v, font, vs)


func _draw_vignettes(v: PlayerVitals, vs: Vector2) -> void:
	var cold := 0.0
	var heat := 0.0
	if v.temperature_enabled and survival.is_active():
		cold = clampf((36.3 - v.body_temp) / 1.8, 0.0, 1.0)
		heat = clampf((v.body_temp - 38.3) / 1.2, 0.0, 1.0)
	var low_hp := clampf(1.0 - v.health / (v.health_max() * 0.3), 0.0, 1.0) if survival.is_active() else 0.0
	var red := maxf(_hurt_flash, low_hp * (0.35 + 0.15 * sin(Time.get_ticks_msec() / 250.0)))
	for p: Array in [[red, Color(0.7, 0.0, 0.0)], [cold * 0.7, Color(0.6, 0.8, 1.0)], [heat * 0.6, Color(1.0, 0.55, 0.15)]]:
		var k: float = p[0]
		if k <= 0.01:
			continue
		var c: Color = p[1]
		# Рамка из полос с убывающей прозрачностью.
		for i in 8:
			var w := 10.0 + i * 10.0
			var a := k * 0.16 * (1.0 - i / 8.0)
			var col := Color(c, a)
			draw_rect(Rect2(0, 0, vs.x, w), col)
			draw_rect(Rect2(0, vs.y - w, vs.x, w), col)
			draw_rect(Rect2(0, w, w, vs.y - 2.0 * w), col)
			draw_rect(Rect2(vs.x - w, w, w, vs.y - 2.0 * w), col)


func _draw_clock(font: Font, vs: Vector2) -> void:
	var clock := survival.clock
	var h24 := String(Settings.get_value("time_format")) != "12"
	var t := "%s · день %d · %s" % [clock.time_text(h24), clock.day, GameClock.SEASON_NAMES.get(clock.season(), "")]
	_text(font, Vector2(vs.x - 16.0, 26.0), t, 16, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_effects(v: PlayerVitals, font: Font, vs: Vector2) -> void:
	var x := vs.x - 16.0 - BADGE
	var y := 40.0
	for e in v.effects:
		var def: Dictionary = v.effect_defs.get(StringName(e["id"]), {})
		var col: Color = def.get("color", Color.GRAY)
		var r := Rect2(x, y, BADGE, BADGE)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(r.grow(-2), Color(col, 0.85))
		var kind := String(def.get("kind", ""))
		draw_rect(r, Color(0.3, 1.0, 0.4) if kind == "buff" else (Color(1, 0.3, 0.3) if kind == "disease" else Color(1, 0.8, 0.4)), false, 2.0)
		_text(font, Vector2(x + BADGE * 0.5, y + 22.0), String(def.get("abbr", "?")), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		var left := float(e["left"])
		var tl := "∞" if left < 0.0 else effect_time(left)
		_text(font, Vector2(x + BADGE * 0.5, y + BADGE + 13.0), tl, 11, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
		x -= BADGE + 8.0


## Температура в единицах из настроек (°C или °F). digits — знаков после запятой.
static func temp_text(celsius: float, digits: int = 0, signed: bool = false) -> String:
	var f := String(Settings.get_value("temperature_unit")) == "f"
	var v := celsius * 1.8 + 32.0 if f else celsius
	var fmt := "%" + ("+" if signed else "") + "." + str(digits) + "f %s"
	return fmt % [v, "°F" if f else "°C"]


## Остаток стадии в игровых часах → «2 ч», «35 мин».
static func effect_time(hours: float) -> String:
	if hours >= 1.0:
		return "%d ч" % ceili(hours)
	return "%d мин" % maxi(1, ceili(hours * 60.0))


func _bar(pos: Vector2, k: float, col: Color, label: String, font: Font) -> void:
	draw_rect(Rect2(pos, Vector2(BAR_W, BAR_H)), Color(0, 0, 0, 0.5))
	var w := (BAR_W - 2.0) * clampf(k, 0.0, 1.0)
	draw_rect(Rect2(pos + Vector2(1, 1), Vector2(w, BAR_H - 2.0)), col)
	if k < 0.2:
		var a := 0.4 + 0.4 * sin(Time.get_ticks_msec() / 160.0)
		draw_rect(Rect2(pos, Vector2(BAR_W, BAR_H)), Color(1, 0.2, 0.2, a), false, 1.5)
	if label != "":
		_text(font, pos + Vector2(2, -2), label, 11, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_LEFT)


func _text(font: Font, pos: Vector2, text: String, fsize: int, col: Color, align: HorizontalAlignment) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
