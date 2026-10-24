class_name StatusScreen
extends CanvasLayer
## Экран состояния персонажа (клавиша C, раздел 4.3): все параметры выживания с числами,
## окружение (воздух, тепло, одежда), болезни и баффы со стадией, симптомами, лечением и
## остатком времени, сложность, время и точка возрождения. Обновляется раз в 0,25 с.

signal closed()

var survival: SurvivalController
var player: Player

var _left: RichTextLabel
var _right: RichTextLabel
var _refresh := 0.0


func _ready() -> void:
	layer = 20
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 560)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	var title := Label.new()
	title.text = "Состояние персонажа"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	root.add_child(cols)
	_left = _rich(cols)
	_right = _rich(cols)
	var hint := Label.new()
	hint.text = "C или Esc — закрыть"
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	root.add_child(hint)
	_update()


func _rich(parent: Control) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(r)
	return r


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.25
		_update()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"stats") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"inventory"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


func _update() -> void:
	if survival == null:
		return
	var v := survival.vitals
	var c := v.cfg
	var env := survival.env
	var t := PackedStringArray()
	t.append("[b]Параметры[/b]")
	t.append(_line("Здоровье", "%d / %d" % [ceili(v.health), int(v.health_max())], v.health / v.health_max()))
	t.append(_line("Сытость", "%d / 100" % roundi(v.hunger), v.hunger / 100.0))
	t.append(_line("Вода", "%d / 100" % roundi(v.thirst) if v.thirst_enabled else "выкл.", v.thirst / 100.0))
	t.append(_line("Выносливость", "%d / %d%s" % [roundi(v.stamina), int(v.stamina_max()), " (выдохся)" if v.exhausted else ""], v.stamina / v.stamina_max()))
	t.append(_line("Бодрость", "%d / 100%s" % [roundi(100.0 - v.fatigue), " — пора спать" if v.is_tired() else ""], 1.0 - v.fatigue / 100.0))
	var bt_note := ""
	if v.body_temp < float(c.get("hypothermia", 35.0)):
		bt_note = " — [color=#8cc0ff]переохлаждение[/color]"
	elif v.body_temp > float(c.get("heatstroke", 39.3)):
		bt_note = " — [color=#ffa060]перегрев[/color]"
	t.append("Температура тела: [b]%s[/b]%s" % [SurvivalHud.temp_text(v.body_temp, 1), bt_note if v.temperature_enabled else " (выкл.)"])
	t.append("Мокрость: %d%%" % roundi(v.wetness * 100.0))
	t.append("Воздух: %.0f с" % v.air)
	t.append("Скорость: %d%%%s" % [roundi(v.speed_mult() * 100.0), "" if v.can_sprint() else " · бег недоступен"])
	t.append("")
	t.append("[b]Окружение[/b]")
	t.append("Воздух: %s · тепло рядом: +%.0f° · укрытие: %s" % [SurvivalHud.temp_text(float(env.get("ambient", 0.0)), 0, true),
		float(env.get("heat", 0.0)), "да" if int(env.get("sky", 15)) < 8 else "нет"])
	t.append("Одежда: утепление +%.0f° · влагостойкость %d%%" % [player.inventory.insulation_total(), roundi(player.inventory.water_resist_total() * 100.0)])
	t.append("Ощущается: [b]%s[/b] (комфорт %s…%s)" % [SurvivalHud.temp_text(v.perceived, 0, true),
		SurvivalHud.temp_text(float(c.get("comfort_low", 14))), SurvivalHud.temp_text(float(c.get("comfort_high", 28)))])
	var bi := String(env.get("biome", ""))
	if bi != "" and Registry.has_entry("biomes", StringName(bi)):
		t.append("Биом: %s" % Registry.get_entry("biomes", StringName(bi))["name"]["ru"])
	t.append("")
	var clock := survival.clock
	t.append("[b]Мир[/b]")
	t.append("День %d, %s · %s, день %d из %d" % [clock.day, clock.time_text(String(Settings.get_value("time_format")) != "12"),
		GameClock.SEASON_NAMES.get(clock.season(), ""), clock.season_day(), clock.season_length])
	t.append("Сложность: %s" % String(v.diff.get("name", {}).get("ru", "—")))
	t.append("Возрождение: %s" % ("у кровати" if survival.spawn.has("bed") else "точка мира"))
	_left.text = "\n".join(t)

	var r := PackedStringArray()
	r.append("[b]Болезни и эффекты[/b]")
	if v.effects.is_empty():
		r.append("[color=#a0a0a0]Нет. Вы здоровы.[/color]")
	for e in v.effects:
		var def: Dictionary = v.effect_defs.get(StringName(e["id"]), {})
		var st := v.stage_of(StringName(e["id"]))
		var col := Color(def.get("color", Color.GRAY)).to_html(false)
		var left := float(e["left"])
		var stages: Array = def.get("stages", [])
		var head := "[color=#%s]■[/color] [b]%s[/b]" % [col, def.get("name", {}).get("ru", String(e["id"]))]
		if stages.size() > 1:
			head += " — стадия %d/%d «%s»" % [int(e["stage"]) + 1, stages.size(), st.get("name", {}).get("ru", "")]
		head += " · %s" % ("пока не вылечить" if left < 0.0 else "ещё " + SurvivalHud.effect_time(left))
		r.append(head)
		r.append("    Симптомы: %s" % st.get("symptoms", {}).get("ru", "—"))
		if String(def.get("kind", "")) != "buff":
			r.append("    Лечение: %s" % def.get("treatment", {}).get("ru", "—"))
	_right.text = "\n".join(r)


static func _line(name: String, value: String, k: float) -> String:
	var n := 12
	var full := clampi(roundi(k * n), 0, n)
	var col := "#e05050" if k < 0.25 else ("#e0c050" if k < 0.5 else "#70c070")
	return "%s: [b]%s[/b]  [color=%s]%s[/color][color=#404040]%s[/color]" % [name, value, col, "█".repeat(full), "█".repeat(n - full)]
