class_name Animal
extends RefCounted
## Одно животное (этап 9): данные для сохранения (вид, место, здоровье, время рождения, сытость,
## любовь, отдых после рождения детёныша, сроки продукции) и состояние ИИ, которое не сохраняется.
## Время — абсолютные игровые минуты (GameClock.total_minutes). Координаты — double.

enum State { IDLE, WANDER, FOLLOW, FEEDER, MATE, FLEE }

var uid := 0
var kind := 0
var id: StringName
var x := 0.0
var y := 0.0
var z := 0.0
var yaw := 0.0
var health := 10.0
var born := 0.0
var fed_until := 0.0
var love_until := 0.0
var breed_after := 0.0
## Срок следующей продукции по индексу в products вида.
var next := PackedFloat64Array()
## Когда последний раз находилась вода рядом (абс. минуты; −1 — не проверяли).
var water_seen := -1.0

# --- ИИ (не сохраняется) ---
var state := State.IDLE
var timer := 0.0
var tx := 0.0
var tz := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var flee_from := Vector3.ZERO
var walk_phase := 0.0
var speed_now := 0.0
var graze := 0.0
var rest := 0.0
var lod_skip := 0
var body: VoxelBody


func to_dict() -> Dictionary:
	return { "uid": uid, "id": String(id), "x": x, "y": y, "z": z, "yaw": yaw, "health": health, "born": born,
		"fed": fed_until, "love": love_until, "breed": breed_after, "next": Array(next), "water": water_seen }


static func from_dict(d: Dictionary) -> Animal:
	var a := Animal.new()
	a.uid = int(d.get("uid", 0))
	a.id = StringName(d.get("id", ""))
	a.x = float(d.get("x", 0.0))
	a.y = float(d.get("y", 0.0))
	a.z = float(d.get("z", 0.0))
	a.yaw = float(d.get("yaw", 0.0))
	a.health = float(d.get("health", 10.0))
	a.born = float(d.get("born", 0.0))
	a.fed_until = float(d.get("fed", 0.0))
	a.love_until = float(d.get("love", 0.0))
	a.breed_after = float(d.get("breed", 0.0))
	a.next = PackedFloat64Array(d.get("next", []))
	a.water_seen = float(d.get("water", -1.0))
	return a
