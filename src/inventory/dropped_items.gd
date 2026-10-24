class_name DroppedItems
extends Node3D
## Предметы на земле (выпали из блоков, выброшены игроком, высыпались из сундука).
## Каждый — маленькое AABB-тело (VoxelBody, координаты в double) и спрайт иконки. Подбираются,
## когда игрок рядом и задержка прошла; одинаковые лежащие рядом сливаются. Сохраняются в
## world.json, исчезают через DESPAWN_SEC.

signal picked_up(stack: ItemStack)

const PICKUP_RADIUS := 1.6
const MAGNET_RADIUS := 2.6
const MERGE_RADIUS := 0.9
const DESPAWN_SEC := 600.0
const GRAVITY := 24.0
const MAX_ITEMS := 400

var world: World
## Кто подбирает: PlayerInventory и тело игрока.
var inventory: PlayerInventory
var player_body: VoxelBody

var _items: Array[_Dropped] = []
var _merge_timer := 0.0


class _Dropped:
	var stack: ItemStack
	var body: VoxelBody
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var age := 0.0
	var delay := 0.5
	var sprite: Sprite3D


func count() -> int:
	return _items.size()


func setup(p_world: World) -> void:
	world = p_world
	world.items_dropped.connect(_on_items_dropped)


func _on_items_dropped(x: float, y: float, z: float, stacks: Array) -> void:
	for s: ItemStack in stacks:
		spawn(s, x, y, z, randf_range(-1.5, 1.5), 4.0, randf_range(-1.5, 1.5), 0.4)


## Бросить предмет в мир (мировые координаты, начальная скорость, задержка подбора).
func spawn(stack: ItemStack, x: float, y: float, z: float, vx: float = 0.0, vy: float = 0.0, vz: float = 0.0,
		delay: float = 0.5) -> void:
	if stack == null or stack.is_empty():
		return
	if _items.size() >= MAX_ITEMS:
		_remove(0)
	var d := _Dropped.new()
	d.stack = stack
	d.body = VoxelBody.new(world.is_solid)
	d.body.half_width = 0.14
	d.body.height = 0.28
	d.body.set_position(x, y, z)
	d.vx = vx
	d.vy = vy
	d.vz = vz
	d.delay = delay
	d.sprite = Sprite3D.new()
	d.sprite.texture = ItemIcons.shared().icon(stack.id)
	d.sprite.pixel_size = 0.4 / 64.0
	d.sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	d.sprite.shaded = true
	d.sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	d.sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(d.sprite)
	_items.append(d)
	_place(d, 0.0)


func _physics_process(delta: float) -> void:
	var i := 0
	while i < _items.size():
		var d := _items[i]
		d.age += delta
		if d.age > DESPAWN_SEC or not world.is_loaded(floori(d.body.x), floori(d.body.z)):
			if d.age > DESPAWN_SEC:
				_remove(i)
				continue
			i += 1
			continue
		if _try_pickup(d):
			_remove(i)
			continue
		d.vy -= GRAVITY * delta
		var drag := 0.92 if d.body.on_ground else 0.99
		d.vx *= drag
		d.vz *= drag
		d.body.move(d.vx * delta, d.vy * delta, d.vz * delta)
		if d.body.on_ground:
			d.vy = 0.0
		if d.body.hit_wall:
			d.vx *= -0.3
			d.vz *= -0.3
		i += 1
	_merge_timer -= delta
	if _merge_timer <= 0.0:
		_merge_timer = 1.0
		_merge()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for d in _items:
		_place(d, t)


func _place(d: _Dropped, t: float) -> void:
	d.sprite.position = world.to_scene(d.body.x, d.body.y, d.body.z) + Vector3(0, 0.22 + sin(t * 2.0 + d.age) * 0.05, 0) + Vector3(world.origin)


func _try_pickup(d: _Dropped) -> bool:
	if inventory == null or player_body == null or d.age < d.delay:
		return false
	var dx := player_body.x - d.body.x
	var dy := (player_body.y + 0.9) - d.body.y
	var dz := player_body.z - d.body.z
	var dist := sqrt(dx * dx + dy * dy + dz * dz)
	if dist > MAGNET_RADIUS:
		return false
	if dist > PICKUP_RADIUS:
		# Притягивается к игроку.
		var k := 6.0 / maxf(dist, 0.1)
		d.vx = dx * k
		d.vz = dz * k
		d.vy = maxf(d.vy, dy * k)
		return false
	var before := d.stack.count
	inventory.add(d.stack)
	if d.stack.count != before:
		picked_up.emit(ItemStack.make(d.stack.id, before - d.stack.count, d.stack.data))
		d.sprite.texture = ItemIcons.shared().icon(d.stack.id)
	return d.stack.count == 0


func _merge() -> void:
	for a in range(_items.size()):
		var da := _items[a]
		if da.stack.count == 0:
			continue
		for b in range(a + 1, _items.size()):
			var db := _items[b]
			if db.stack.count == 0 or not da.stack.can_merge(db.stack):
				continue
			if absf(da.body.x - db.body.x) > MERGE_RADIUS or absf(da.body.y - db.body.y) > MERGE_RADIUS \
					or absf(da.body.z - db.body.z) > MERGE_RADIUS:
				continue
			var def := world.registry.item(da.stack.id)
			var limit := def.stack if def != null else 64
			var n := mini(limit - da.stack.count, db.stack.count)
			da.stack.count += n
			db.stack.count -= n
	var i := 0
	while i < _items.size():
		if _items[i].stack.count == 0:
			_remove(i)
		else:
			i += 1


func _remove(i: int) -> void:
	_items[i].sprite.queue_free()
	_items.remove_at(i)


## Для world.json: [{x, y, z, item}].
func to_array() -> Array:
	var out := []
	for d in _items:
		out.append({ "x": d.body.x, "y": d.body.y, "z": d.body.z, "age": d.age, "item": d.stack.to_dict() })
	return out


func from_array(arr: Array) -> void:
	for e: Variant in arr:
		if not e is Dictionary:
			continue
		var s := ItemStack.from_dict(e.get("item", {}))
		if s == null or world.registry.item(s.id) == null:
			continue
		spawn(s, float(e["x"]), float(e["y"]), float(e["z"]), 0.0, 0.0, 0.0, 0.0)
		_items[-1].age = float(e.get("age", 0.0))
