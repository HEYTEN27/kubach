class_name AnimalView
extends Node3D
## Вид животного (этап 9): модель из коробок data/animals.json → model, сгруппированных по
## анимации (ноги в противофазе, голова, хвост, руно). Меши вида строятся один раз и делятся
## между всеми животными этого вида (кэш build_parts). Узор — шейдер animal.gdshader.

const PATTERNS := ["hair", "spots", "wool", "feathers", "skin", "horn", "eye", "beak"]

static var _cache := {}    # id вида → Array[{ anim, pivot: Vector3, mesh }]
static var _material: ShaderMaterial
static var _hurt_material: ShaderMaterial

var parts: Array[MeshInstance3D] = []
var anims: PackedStringArray = []
var _hurt := 0.0
var _t := 0.0
var _was_hurt := false


## Части модели вида: группы по (anim, pivot), вершины — относительно шарнира группы, в блоках.
static func build_parts(def: Dictionary) -> Array:
	var id := String(def["id"])
	if _cache.has(id):
		return _cache[id]
	var base := Color(def.get("color", Color(0.6, 0.5, 0.4)))
	var groups := {}   # ключ → { anim, pivot, verts… }
	for part: Dictionary in def.get("model", []):
		var f := Vector3(part["from"][0], part["from"][1], part["from"][2])
		var t := Vector3(part["to"][0], part["to"][1], part["to"][2])
		var anim := String(part.get("anim", ""))
		var pv: Array = part.get("pivot", [])
		var pivot := Vector3.ZERO
		if pv.size() == 3:
			pivot = Vector3(pv[0], pv[1], pv[2])
		elif anim in ["leg_a", "leg_b"]:
			pivot = Vector3((f.x + t.x) * 0.5, t.y, (f.z + t.z) * 0.5)
		var key := "%s|%s" % [anim, pivot]
		if not groups.has(key):
			groups[key] = { "anim": anim, "pivot": pivot / 16.0, "v": PackedVector3Array(), "n": PackedVector3Array(),
				"c": PackedColorArray(), "c2": PackedFloat32Array(), "i": PackedInt32Array() }
		var c1 := Color(part.get("color", Color(0, 0, 0, 0)))
		if c1.a == 0.0:
			c1 = base
		var c2 := Color(part.get("color2", Color(0, 0, 0, 0)))
		if c2.a == 0.0:
			c2 = c1.darkened(0.25)
		var pat := PATTERNS.find(String(part.get("pattern", "hair")))
		_box(groups[key], (f - pivot) / 16.0, (t - pivot) / 16.0, c1, Color(c2.r, c2.g, c2.b, maxi(pat, 0) / 10.0))
	var out := []
	for key: String in groups:
		var g: Dictionary = groups[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g["v"]
		arr[Mesh.ARRAY_NORMAL] = g["n"]
		arr[Mesh.ARRAY_COLOR] = g["c"]
		arr[Mesh.ARRAY_CUSTOM0] = g["c2"]
		arr[Mesh.ARRAY_INDEX] = g["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, material())
		out.append({ "anim": g["anim"], "pivot": g["pivot"], "mesh": mesh })
	_cache[id] = out
	return out


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://src/livestock/animal.gdshader")
	return _material


static func _box(g: Dictionary, a: Vector3, b: Vector3, c1: Color, c2: Color) -> void:
	var faces := [
		[Vector3.RIGHT, [Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z)]],
		[Vector3.LEFT, [Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z)]],
		[Vector3.UP, [Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z)]],
		[Vector3.DOWN, [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]],
		[Vector3.BACK, [Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]],
		[Vector3.FORWARD, [Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z)]],
	]
	var verts: PackedVector3Array = g["v"]
	var norms: PackedVector3Array = g["n"]
	var cols: PackedColorArray = g["c"]
	var c2s: PackedFloat32Array = g["c2"]
	var idx: PackedInt32Array = g["i"]
	for fc: Array in faces:
		var n: Vector3 = fc[0]
		var base := verts.size()
		for v: Vector3 in fc[1]:
			verts.append(v)
			norms.append(n)
			cols.append(c1)
			c2s.append_array([c2.r, c2.g, c2.b, c2.a])
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	g["v"] = verts
	g["n"] = norms
	g["c"] = cols
	g["c2"] = c2s
	g["i"] = idx


func setup(def: Dictionary) -> void:
	for p: Dictionary in build_parts(def):
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.position = p["pivot"]
		add_child(mi)
		parts.append(mi)
		anims.append(String(p["anim"]))


## Кадр: ход (фаза шага и скорость), щипание травы, стрижка, вспышка урона.
func animate(delta: float, phase: float, moving: float, graze: float, sheared: bool) -> void:
	_t += delta
	_hurt = maxf(0.0, _hurt - delta * 2.5)
	var swing := sin(phase) * 0.5 * clampf(moving, 0.0, 1.0)
	for i in parts.size():
		var mi := parts[i]
		match anims[i]:
			"leg_a":
				mi.rotation.x = swing
			"leg_b":
				mi.rotation.x = -swing
			"head":
				mi.rotation.x = graze * 0.9 + sin(_t * 1.3) * 0.04
				mi.rotation.y = sin(_t * 0.37) * 0.15 * (1.0 - graze)
			"tail":
				mi.rotation.z = sin(_t * 4.0) * 0.25
			"wool":
				mi.visible = not sheared
	if _was_hurt and _hurt <= 0.0:
		for mi in parts:
			mi.material_override = null
	_was_hurt = _hurt > 0.0


## Покраснеть от удара на ~0,4 с: общий «красный» материал вместо обычного (instance uniform
## не годится — их буфер уже занят).
func flash_hurt() -> void:
	_hurt = 1.0
	if _hurt_material == null:
		_hurt_material = material().duplicate()
		_hurt_material.set_shader_parameter(&"hurt", 1.0)
	for mi in parts:
		mi.material_override = _hurt_material
