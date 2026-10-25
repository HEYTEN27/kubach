class_name CraftingData
extends RefCounted
## Данные ремесла (раздел 5 ТЗ) в удобном виде: материалы и из каких предметов они
## получаются, части, инструменты из частей, уровни качества, сплавы, станции и рецепты по
## станциям. Строится один раз из ContentRegistry; общий экземпляр — shared().
##
## Качество: уровень 0…4 (Плохое…Шедевр) хранится в данных стопки "quality". Балл 0…1 —
## промежуточная величина: из баллов входов, мини-игры и станции считается балл результата,
## а из него — уровень (min_score в data/qualities.json).

## Балл мини-игры в авто-режиме (настройка «Мини-игры» выключена) и у рецептов без мини-игры.
const AUTO_SCORE := 0.55
const PLAIN_SCORE := 0.5
## Балл входа без качества (сырьё).
const RAW_SCORE := 0.4

static var _shared: CraftingData
static var _shared_reg_id := 0

var registry: ContentRegistry
var materials := {}        # StringName → запись
var parts := {}            # StringName → запись
var tool_types := {}       # StringName → запись
var alloys: Array[Dictionary] = []
var stations := {}         # StringName → запись
var recipes := {}          # StringName → запись
var by_station := {}       # StringName станции → Array[Dictionary] по order
var qualities: Array[Dictionary] = []
## id предмета → id материала (слиток → металл, доски → порода, бечёвка → обмотка).
var item_material := {}


static func shared(reg: ContentRegistry) -> CraftingData:
	if _shared == null or _shared_reg_id != reg.get_instance_id():
		_shared = CraftingData.new(reg)
		_shared_reg_id = reg.get_instance_id()
	return _shared


func _init(reg: ContentRegistry) -> void:
	registry = reg
	for e in reg.get_entries("materials"):
		materials[StringName(e["id"])] = e
	for e in reg.get_entries("parts"):
		parts[StringName(e["id"])] = e
	for e in reg.get_entries("tool_types"):
		tool_types[StringName(e["id"])] = e
	for e in reg.get_entries("alloys"):
		alloys.append(e)
	for e in reg.get_entries("stations"):
		stations[StringName(e["id"])] = e
	var q := reg.get_entries("qualities")
	q.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	qualities = q
	for e in reg.get_entries("recipes"):
		var id := StringName(e["id"])
		recipes[id] = e
		var st := StringName(e["station"])
		if not by_station.has(st):
			by_station[st] = []
		(by_station[st] as Array).append(e)
	for st: StringName in by_station:
		(by_station[st] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["category"]) + "%04d" % int(a["order"]) < String(b["category"]) + "%04d" % int(b["order"]))
	# Материалы предметов: явные источники, затем все предметы с тегом.
	for mid: StringName in materials:
		var m: Dictionary = materials[mid]
		for src: String in m.get("sources", []):
			item_material[StringName(src)] = mid
		var tags: Array = m.get("source_tags", [])
		if not tags.is_empty():
			for d in reg.items():
				for t: String in tags:
					if d.tags.has(t) and not item_material.has(d.id):
						item_material[d.id] = mid


# --- материалы -----------------------------------------------------------------------------

## Материал стопки: у частей и сплавов — из данных, у сырья — по предмету. Пусто — не материал.
func material_of(s: ItemStack) -> StringName:
	if s == null:
		return &""
	if s.data.has("material"):
		return StringName(s.data["material"])
	return item_material.get(s.id, &"")


func material(id: StringName) -> Dictionary:
	return materials.get(id, {})


## Прилагательное материала нужного рода: «стальная», «дубовое».
func material_adj(id: StringName, gender: String, locale: String = "ru") -> String:
	var m := material(id)
	if m.is_empty():
		return String(id)
	var a: Dictionary = m.get("adj", {})
	if locale == "en":
		return String(a.get("en", m["name"].get("en", id)))
	var v := String(a.get(gender, ""))
	return v if v != "" else String(m["name"].get("ru", id))


func material_name(id: StringName, locale: String = "ru") -> String:
	var m := material(id)
	return String(m["name"].get(locale, m["name"].get("ru", id))) if not m.is_empty() else String(id)


# --- качество -----------------------------------------------------------------------------

func quality_level(score: float) -> int:
	var lvl := 0
	for q in qualities:
		if score >= float(q["min_score"]) - 0.0001:
			lvl = int(q["order"])
	return lvl


## Балл уровня как входа следующего шага; у стопки без качества — RAW_SCORE.
func quality_score(level: int) -> float:
	for q in qualities:
		if int(q["order"]) == level:
			return float(q["score"])
	return RAW_SCORE


func stack_score(s: ItemStack) -> float:
	return quality_score(int(s.data["quality"])) if s.data.has("quality") else RAW_SCORE


func quality_mult(level: int) -> float:
	for q in qualities:
		if int(q["order"]) == level:
			return float(q["mult"])
	return 1.0


func quality_name(level: int, locale: String = "ru") -> String:
	for q in qualities:
		if int(q["order"]) == level:
			return String(q["name"].get(locale, q["name"]["ru"]))
	return "?"


func quality_color(level: int) -> Color:
	for q in qualities:
		if int(q["order"]) == level:
			return q["color"]
	return Color.WHITE


## Балл результата: входы и мастерство поровну, плюс бонус станции и навыка (этап 15).
static func combine_score(inputs_score: float, game_score: float, station_bonus: float, skill_bonus: float = 0.0) -> float:
	return clampf(0.45 * inputs_score + 0.45 * game_score + station_bonus + skill_bonus, 0.0, 1.0)


# --- предметы и рецепты -------------------------------------------------------------------

func has_tag(item_id: StringName, tag: String) -> bool:
	var d := registry.item(item_id)
	return d != null and d.tags.has(tag)


## Подходит ли стопка ко входу рецепта { id, tag, count }.
func input_matches(input: Dictionary, s: ItemStack) -> bool:
	if s == null:
		return false
	var iid := String(input.get("id", ""))
	if iid != "":
		return String(s.id) == iid
	var tag := String(input.get("tag", ""))
	return tag != "" and has_tag(s.id, tag)


func fuel_of(item_id: StringName) -> Dictionary:
	var d := registry.item(item_id)
	return d.fuel if d != null else {}


func station(id: StringName) -> Dictionary:
	return stations.get(id, {})


func recipes_for(station_id: StringName) -> Array:
	return by_station.get(station_id, [])


func recipe(id: StringName) -> Dictionary:
	return recipes.get(id, {})


## Название рецепта: своё или по выходу.
func recipe_name(r: Dictionary, locale: String = "ru") -> String:
	var n: Dictionary = r.get("name", {})
	if String(n.get(locale, "")) != "":
		return String(n[locale])
	match String(r.get("op", "craft")):
		"assemble":
			var tt: Dictionary = tool_types.get(StringName(r.get("tool_type", "")), {})
			return "Сборка: %s" % String(tt.get("name", {}).get(locale, r.get("tool_type", ""))).to_lower() if locale == "ru" else "Assemble: %s" % tt.get("name", {}).get("en", "")
		"repair":
			return "Ремонт" if locale == "ru" else "Repair"
		"salvage":
			return "Разборка" if locale == "ru" else "Salvage"
		"quench":
			return "Закалка навершия" if locale == "ru" else "Quench"
		"sharpen":
			return "Заточка" if locale == "ru" else "Sharpen"
		"dye":
			return "Крашение ткани" if locale == "ru" else "Dye cloth"
		"alloy":
			for a in alloys:
				if String(a["id"]) == String(r.get("tool_type", "")):
					return ("Сплав: %s" if locale == "ru" else "Alloy: %s") % String(a["name"].get(locale, a["name"]["ru"])).to_lower()
	var out: Dictionary = r.get("output", {})
	var d := registry.item(StringName(out.get("id", "")))
	return d.display_name(locale) if d != null else String(r["id"])


## Описание входа для книги рецептов: «Бечёвка ×3», «любые доски ×4».
func input_text(input: Dictionary, locale: String = "ru") -> String:
	var n := int(input.get("count", 1))
	var iid := String(input.get("id", ""))
	if iid != "":
		var d := registry.item(StringName(iid))
		return "%s ×%d" % [d.display_name(locale) if d != null else iid, n]
	return "%s ×%d" % [TAG_NAMES.get(String(input.get("tag", "")), "#" + String(input.get("tag", ""))), n]


const TAG_NAMES := {
	"log": "любое бревно", "planks": "любые доски", "rock": "любой камень", "ingot": "слитки одного металла",
	"cloth": "любая ткань", "dye": "любая краска", "bowl": "миска", "cup": "кружка", "tannin": "дубильная кора",
	"torch_fuel": "уголь", "thread": "нить или пряжа", "fuel": "топливо",
}
