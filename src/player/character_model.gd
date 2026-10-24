class_name CharacterModel
extends Node3D
## Модель персонажа из коробок (раздел 4.2 ТЗ): тип тела, рост, телосложение, кожа, лицо
## (глаза, брови, нос, рот, шрамы — пиксели на текстуре лица 8×8), причёска и борода из
## data/hairstyles.json и data/beards.json, одежда и экипировка (поле model предметов).
## Анимации: ходьба, удар, «дыхание» в покое, подскок при смене экипировки.
##
## Внешность — словарь (см. default_appearance()); хранится в world.json → player.appearance.

const PX := 0.055   # «пиксель» головы: голова 8×8×8 при масштабе 1
const UNDERSHIRT := Color(0.78, 0.75, 0.68)
const UNDERPANTS := Color(0.36, 0.32, 0.26)

var registry: ContentRegistry
var appearance := {}

var _root: Node3D
var _head: Node3D
var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _hand_r: Node3D
var _hand_l: Node3D
var _phase := 0.0
var _swing := 0.0
var _idle := 0.0
var _react := 0.0
var _equip: Inventory
var _held_icon: Sprite3D
var _offhand_light: OmniLight3D
var _mats := {}


static func default_appearance() -> Dictionary:
	return {
		"body": "a", "height": 1.0, "build": 0.5,
		"skin": "#dca582", "face": "calm",
		"eyes": "eyes_round", "brows": "brows_thin", "nose": "nose_small", "mouth": "mouth_neutral",
		"eye_color": "#3a5a8a", "hair": "short", "hair_color": "#5a3a22", "beard": "none", "scars": [],
	}


## Случайная внешность (для жителей позже и кнопки «случайно» в редакторе).
static func random_appearance(registry: ContentRegistry, rng: RandomNumberGenerator) -> Dictionary:
	var a := default_appearance()
	var pick := func(cat: String) -> String:
		var list := registry.get_entries(cat)
		return list[rng.randi() % list.size()]["id"] if not list.is_empty() else ""
	var palette := func(id: String) -> String:
		var cols: Array = registry.get_entry("palettes", StringName(id)).get("colors", [Color.GRAY])
		return (cols[rng.randi() % cols.size()] as Color).to_html(false)
	a["body"] = "a" if rng.randf() < 0.5 else "b"
	a["height"] = snappedf(rng.randf_range(0.92, 1.08), 0.01)
	a["build"] = snappedf(rng.randf_range(0.2, 0.8), 0.01)
	a["skin"] = palette.call("skin")
	a["hair"] = pick.call("hairstyles")
	a["hair_color"] = palette.call("hair")
	a["eye_color"] = palette.call("eyes")
	a["beard"] = pick.call("beards") if a["body"] == "a" and rng.randf() < 0.6 else "none"
	var preset: Dictionary = registry.get_entries("face_presets")[rng.randi() % registry.get_entries("face_presets").size()]
	for k in ["eyes", "brows", "nose", "mouth"]:
		a[k] = String(preset[k])
	a["face"] = String(preset["id"])
	return a


func setup(p_registry: ContentRegistry, p_appearance: Dictionary = {}) -> void:
	registry = p_registry
	appearance = default_appearance()
	appearance.merge(p_appearance, true)
	rebuild()


func set_appearance(a: Dictionary) -> void:
	appearance = default_appearance()
	appearance.merge(a, true)
	rebuild()


## Экипировка игрока (слоты PlayerInventory.EQUIP_KINDS) — одежда и броня на модели.
func set_equipment(equip: Inventory) -> void:
	_equip = equip
	rebuild()
	_react = 1.0


## Предмет в правой руке (иконка) — для вида от третьего лица и окна инвентаря.
func set_held(stack: ItemStack) -> void:
	if _held_icon == null:
		return
	_held_icon.visible = stack != null
	if stack != null:
		_held_icon.texture = ItemIcons.shared().icon(stack.id)


func rebuild() -> void:
	if registry == null:
		return
	if _root != null:
		_root.free()
	_mats.clear()
	_root = Node3D.new()
	add_child(_root)
	var a := appearance
	var body := registry.get_entry("body_types", StringName(a.get("body", "a")))
	var sh: float = body.get("shoulders", 1.0)
	var hips: float = body.get("hips", 1.0)
	var chest: float = body.get("chest", 0.0)
	var torso_k: float = body.get("torso", 1.0)
	var legs_k: float = body.get("legs", 1.0)
	var head_k: float = body.get("head", 1.0)
	var build := lerpf(0.86, 1.18, float(a.get("build", 0.5)))
	_root.scale = Vector3.ONE * clampf(float(a.get("height", 1.0)), 0.85, 1.15)
	var skin := Color(String(a.get("skin", "#dca582")))

	var leg_h := 0.75 * legs_k
	var torso_h := 0.72 * torso_k
	var torso_w := 0.5 * sh * build
	var torso_d := 0.26 * build
	var limb_w := 0.22 * build
	var leg_w := 0.24 * build * hips

	var shirt := _equip_look(1, UNDERSHIRT)
	var pants := _equip_look(2, UNDERPANTS)
	var boots := _equip_look(3, Color(0, 0, 0, 0))
	var gloves := _equip_look(4, Color(0, 0, 0, 0))

	_leg_l = _limb(Vector3(-leg_w * 0.52, leg_h, 0), Vector3(leg_w, leg_h, leg_w), pants["color"])
	_leg_r = _limb(Vector3(leg_w * 0.52, leg_h, 0), Vector3(leg_w, leg_h, leg_w), pants["color"])
	for leg in [_leg_l, _leg_r]:
		if boots["color"].a > 0.0:
			var bh := leg_h * (0.42 if boots["style"] != "shoes" else 0.14)
			_box(leg, Vector3(0, -leg_h + bh * 0.5, 0), Vector3(leg_w + 0.03, bh, leg_w + 0.03), boots["color"])
		else:
			_box(leg, Vector3(0, -leg_h + 0.04, -0.01), Vector3(leg_w + 0.01, 0.08, leg_w + 0.02), skin.darkened(0.1))

	_torso = Node3D.new()
	_torso.position = Vector3(0, leg_h, 0)
	_root.add_child(_torso)
	_box(_torso, Vector3(0, torso_h * 0.5, 0), Vector3(torso_w, torso_h, torso_d), shirt["color"])
	if chest > 0.0:
		_box(_torso, Vector3(0, torso_h * 0.68, -torso_d * 0.5 - chest * 0.5), Vector3(torso_w * 0.8, torso_h * 0.22, chest),
			shirt["color"])
	if shirt["style"] == "coat":
		_box(_torso, Vector3(0, -0.2, 0), Vector3(torso_w + 0.06, 0.42, torso_d + 0.06), shirt["color"])
		_box(_torso, Vector3(0, torso_h - 0.04, 0), Vector3(torso_w + 0.08, 0.1, torso_d + 0.08), shirt["color"].lightened(0.35))
	if shirt["style"] == "plate":
		_box(_torso, Vector3(0, torso_h * 0.55, 0), Vector3(torso_w + 0.04, torso_h * 0.75, torso_d + 0.05), shirt["color"])
	# Пояс.
	_box(_torso, Vector3(0, 0.03, 0), Vector3(torso_w + 0.01, 0.06, torso_d + 0.01), pants["color"].darkened(0.35))

	var arm_y := leg_h + torso_h - 0.03
	var arm_x := torso_w * 0.5 + limb_w * 0.5
	var sleeve: Color = shirt["color"]
	_arm_l = _limb(Vector3(-arm_x, arm_y, 0), Vector3(limb_w, 0.7, limb_w), sleeve)
	_arm_r = _limb(Vector3(arm_x, arm_y, 0), Vector3(limb_w, 0.7, limb_w), sleeve)
	_hand_l = _hand(_arm_l, skin if gloves["color"].a == 0.0 else gloves["color"], limb_w)
	_hand_r = _hand(_arm_r, skin if gloves["color"].a == 0.0 else gloves["color"], limb_w)

	_head = Node3D.new()
	_head.position = Vector3(0, leg_h + torso_h, 0)
	_head.scale = Vector3.ONE * head_k
	_root.add_child(_head)
	_box(_head, Vector3(0, 0.22, 0), Vector3(0.44, 0.44, 0.44), skin)
	_face(skin)
	var hair_col := Color(String(a.get("hair_color", "#5a3a22")))
	var hat := _equip_look(0, Color(0, 0, 0, 0))
	var hair_entry := registry.get_entry("hairstyles", StringName(a.get("hair", "short")))
	for b: Array in hair_entry.get("boxes", []):
		# Под шапкой видны только волосы ниже её края.
		if hat["color"].a > 0.0 and b[1] >= 6.0:
			continue
		_pixel_box(b, hair_col)
	var beard := registry.get_entry("beards", StringName(a.get("beard", "none")))
	for b: Array in beard.get("boxes", []):
		_pixel_box(b, hair_col.darkened(0.05))
	if hat["color"].a > 0.0:
		_hat(hat)

	var back := _equip_look(5, Color(0, 0, 0, 0))
	if back["color"].a > 0.0:
		var big: bool = back["style"] == "large"
		if back["style"] == "quiver":
			_box(_torso, Vector3(0.1, torso_h * 0.55, torso_d * 0.5 + 0.07), Vector3(0.12, 0.62, 0.12), back["color"])
		else:
			var sz := Vector3(torso_w * (0.9 if big else 0.7), torso_h * (0.95 if big else 0.62), 0.2 if big else 0.14)
			_box(_torso, Vector3(0, torso_h * 0.52, torso_d * 0.5 + sz.z * 0.5), sz, back["color"])
			_box(_torso, Vector3(0, torso_h * 0.36, torso_d * 0.5 + sz.z + 0.03), Vector3(sz.x * 0.6, sz.y * 0.35, 0.06),
				back["color"].darkened(0.2))
	var off := _equip_look(8, Color(0, 0, 0, 0))
	_offhand_light = null
	if off["color"].a > 0.0 or _equip_id(8) != &"":
		_offhand(off)

	_held_icon = Sprite3D.new()
	_held_icon.pixel_size = 0.45 / 64.0
	_held_icon.position = Vector3(0, -0.12, -0.18)
	_held_icon.rotation_degrees = Vector3(0, 90, -45)
	_held_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_held_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_held_icon.visible = false
	_hand_r.add_child(_held_icon)


## Вид экипировки в слоте: { color, style } (цвет — из данных экземпляра или предмета).
func _equip_look(slot: int, fallback: Color) -> Dictionary:
	var out := { "color": fallback, "style": "" }
	if _equip == null:
		return out
	var s := _equip.get_stack(slot)
	if s == null:
		return out
	var d := registry.item(s.id)
	if d == null or d.model.is_empty():
		return out
	out["color"] = Color(String(s.data["color"])) if s.data.has("color") else d.model.get("color", fallback)
	out["style"] = String(d.model.get("style", ""))
	return out


func _equip_id(slot: int) -> StringName:
	if _equip == null:
		return &""
	var s := _equip.get_stack(slot)
	return s.id if s != null else &""


func _hat(hat: Dictionary) -> void:
	var c: Color = hat["color"]
	match hat["style"]:
		"ushanka":
			_pixel_box([-0.7, 5.8, -0.7, 8.7, 9.6, 8.7], c)
			_pixel_box([-0.9, 2.5, 1.0, 0.2, 6.0, 6.5], c.lightened(0.15))
			_pixel_box([7.8, 2.5, 1.0, 8.9, 6.0, 6.5], c.lightened(0.15))
			_pixel_box([-0.8, 5.6, -0.9, 8.8, 6.6, 0.2], c.lightened(0.15))
		"helmet":
			_pixel_box([-0.5, 5.0, -0.5, 8.5, 9.0, 8.5], c)
			_pixel_box([3.5, 2.5, -0.9, 4.5, 5.5, -0.3], c.darkened(0.1))
		_:
			_pixel_box([-0.4, 6.0, -0.4, 8.4, 9.0, 8.4], c)
			_pixel_box([-0.4, 6.0, -1.8, 8.4, 6.5, 0.0], c.darkened(0.15))


func _offhand(off: Dictionary) -> void:
	var id := _equip_id(8)
	var d := registry.item(id)
	if d != null and d.light > 0:
		_box(_hand_l, Vector3(0, -0.05, -0.12), Vector3(0.05, 0.05, 0.4), Color(0.42, 0.29, 0.16), Vector3(-0.6, 0, 0))
		var flame := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.09, 0.12, 0.09)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.65, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.2)
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material = mat
		flame.mesh = m
		flame.position = Vector3(0, 0.1, -0.3)
		_hand_l.add_child(flame)
	elif off["style"] == "shield":
		_box(_arm_l, Vector3(-0.14, -0.4, 0), Vector3(0.06, 0.6, 0.5), off["color"])
		_box(_arm_l, Vector3(-0.18, -0.4, 0), Vector3(0.03, 0.12, 0.12), Color(0.4, 0.4, 0.42))


func _hand(arm: Node3D, color: Color, w: float) -> Node3D:
	var hand := Node3D.new()
	hand.position = Vector3(0, -0.66, 0)
	arm.add_child(hand)
	_box(hand, Vector3(0, -0.02, 0), Vector3(w + 0.01, 0.12, w + 0.01), color)
	return hand


## Текстура лица 8×8: глаза, брови, нос, рот, шрамы поверх кожи.
func _face(skin: Color) -> void:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(skin)
	var a := appearance
	var roles := {
		"white": Color(0.95, 0.94, 0.9), "iris": Color(String(a.get("eye_color", "#3a5a8a"))),
		"dark": skin.darkened(0.55), "hair": Color(String(a.get("hair_color", "#5a3a22"))).darkened(0.1),
		"shade": skin.darkened(0.18), "light": skin.lightened(0.12), "lip": skin.darkened(0.3).lerp(Color(0.6, 0.25, 0.25), 0.4),
		"scar": skin.lightened(0.25).lerp(Color(0.85, 0.6, 0.6), 0.3),
	}
	var parts: Array = [a.get("eyes", ""), a.get("brows", ""), a.get("nose", ""), a.get("mouth", "")]
	parts.append_array(a.get("scars", []))
	for pid: Variant in parts:
		var e := registry.get_entry("face_parts", StringName(String(pid)))
		for p: Array in e.get("pixels", []):
			var x := int(p[0])
			var y := int(p[1])
			if x >= 0 and x < 8 and y >= 0 and y < 8:
				img.set_pixel(x, y, roles.get(String(p[2]), skin))
	var tex := ImageTexture.create_from_image(img)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.44, 0.44)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.85
	qm.material = mat
	quad.mesh = qm
	quad.position = Vector3(0, 0.22, -0.2215)
	quad.rotation.y = PI
	_head.add_child(quad)


## Коробка в «пикселях» головы: [x0, y0, z0, x1, y1, z1], голова 0…8, лицо при z = 0.
func _pixel_box(b: Array, color: Color) -> void:
	var lo := Vector3(float(b[0]), float(b[1]), float(b[2]))
	var hi := Vector3(float(b[3]), float(b[4]), float(b[5]))
	var center := ((lo + hi) * 0.5 - Vector3(4, 0, 4)) * PX
	_box(_head, center, (hi - lo).abs() * PX, color)


## speed — горизонтальная скорость, pitch — наклон головы (рад).
func animate(delta: float, speed: float, pitch: float, crouching: bool) -> void:
	if _root == null:
		return
	_phase += delta * speed * 2.2
	_idle += delta
	var amp := clampf(speed / 4.3, 0.0, 1.4) * 0.7
	var s := sin(_phase) * amp
	var breath := sin(_idle * 1.6) * 0.03 * (1.0 - clampf(speed, 0.0, 1.0))
	_leg_l.rotation.x = s
	_leg_r.rotation.x = -s
	_arm_l.rotation.x = -s * 0.8 + breath
	_arm_l.rotation.z = -0.04 - breath
	_swing = maxf(0.0, _swing - delta * 4.0)
	_arm_r.rotation.x = s * 0.8 - sin(_swing * PI) * 1.4 - breath
	_arm_r.rotation.z = 0.04 + breath
	_head.rotation.x = clampf(-pitch, -1.2, 1.2)
	_torso.rotation.x = 0.35 if crouching else 0.0
	_torso.scale.y = 1.0 + breath * 0.3
	_react = maxf(0.0, _react - delta * 3.0)
	_root.position.y = (-0.25 if crouching else 0.0) + sin(_react * PI) * 0.12


func swing() -> void:
	_swing = 1.0


## Конечность с шарниром в точке pivot; коробка свисает вниз.
func _limb(pivot: Vector3, size: Vector3, color: Color) -> Node3D:
	var joint := Node3D.new()
	joint.position = pivot
	_root.add_child(joint)
	_box(joint, Vector3(0, -size.y * 0.5, 0), size, color)
	return joint


func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	mi.mesh = mesh
	mi.position = center
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	_mats[key] = mat
	return mat
