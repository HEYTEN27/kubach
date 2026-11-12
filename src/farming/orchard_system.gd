class_name OrchardSystem
extends Node
## Сады в игре (этап 9, раздел 8 ТЗ).
## - Саженец (блок sapling_<дерево>) на почве с тегом plantable/soil получает данные блока
##   { type: sapling, tree, p, t } и за grow_days игровых суток вырастает в дерево той же формы,
##   что у генератора (TreeBuilder → WorldTreeWriter → World.apply_changes). Зимой спит; досчёт
##   времени — как у культур (до MAX_CATCHUP_DAYS).
## - Плодовые деревья (поле fruit в data/trees.json): листва по сезонам переключается между
##   обычной, цветущей и с плодами (правило — Orchard.next_variant). Колонны с плодовой листвой
##   пересматриваются раз в RESCAN_MINUTES игровых минут, по бюджету колонн за тик.
## - ПКМ по листве с плодами — сбор (плод выпадает, листва становится обычной).
## - Сломанное бревно без опоры роняет всё дерево (TreeFeller + анимация FallingTree).

const TICK_SEC := 1.0
const COLUMNS_PER_TICK := 4
const SAPLINGS_PER_TICK := 64
const RESCAN_MINUTES := 120.0
const MAX_CATCHUP_DAYS := 30.0

signal tree_grown(pos: Vector3i, tree: StringName)
signal tree_felled(pos: Vector3i, blocks: int)

var world: World
var clock: GameClock
var player: Player
## Анимация падения (в тестах выключена: дерево сразу рассыпается предметами).
var animate := true
var saplings := {}
var stat_ms := 0.0
var felled := 0
var _cols := {}          # Vector2i → минута последнего пересмотра листвы (−1 — ещё не было)
var _left := 0.0
var _rng := RandomNumberGenerator.new()
var _sapling_tree := {}  # блок саженца → индекс дерева в TreeBuilder
var _leaf := {}          # блок листвы плодового → [индекс плодового, вид 0/1/2]
var _fruit_trees: Array[Dictionary] = []   # { blocks: [листва, цвет, плоды], mask, fruit }
var _fruit_ids := PackedInt32Array()
var _log_leaves := {}    # блок бревна → PackedInt32Array листвы этого дерева
var _grow_days := PackedFloat32Array()
var _mesher: Object


func _init() -> void:
	name = "Orchard"
	_rng.randomize()


func setup(p_world: World, p_clock: GameClock, p_player: Player = null) -> void:
	world = p_world
	clock = p_clock
	player = p_player
	var reg := world.registry
	var tb := world.generator.trees
	for t in tb.count:
		var e := reg.get_entry("trees", tb.ids[t])
		_grow_days.append(float(e.get("grow_days", 8.0)) if e.get("grow_days") != null else 8.0)
		var sb := reg.block_num(StringName("sapling_%s" % tb.ids[t]))
		if sb > 0:
			_sapling_tree[sb] = t
		var lv := tb.leaves_block[t]
		var leaf_ids := PackedInt32Array([lv])
		var fruit := String(e.get("fruit", ""))
		if fruit != "" and lv > 0:
			var lname := String(reg.block_by_num(lv).id)
			var bl := reg.block_num(StringName(lname + "_blossom"))
			var fr := reg.block_num(StringName(lname + "_fruit"))
			if bl > 0 and fr > 0 and not _leaf.has(lv):
				var i := _fruit_trees.size()
				_fruit_trees.append({ "blocks": [lv, bl, fr], "mask": Orchard.season_mask(e.get("fruit_seasons", [])),
					"fruit": StringName(fruit) })
				_leaf[lv] = [i, 0]
				_leaf[bl] = [i, 1]
				_leaf[fr] = [i, 2]
				_fruit_ids.append_array([lv, bl, fr])
				leaf_ids.append_array([bl, fr])
		var lg := tb.log_block[t]
		if lg > 0:
			var have: PackedInt32Array = _log_leaves.get(lg, PackedInt32Array())
			for b in leaf_ids:
				if not have.has(b):
					have.append(b)
			_log_leaves[lg] = have
	world.chunks.column_loaded.connect(_on_column_loaded)
	world.chunks.column_unloading.connect(_on_column_unloading)
	world.block_changed.connect(_on_block_changed)
	if world.is_inside_tree():
		EventBus.block_broken.connect(_on_block_broken)


func season_index() -> int:
	return maxi(0, Orchard.SEASONS.find(clock.season()))


## Сколько колонн сейчас пересматривается (есть или может быть плодовая листва).
func tracked_columns() -> int:
	return _cols.size()


func is_fruit_leaves(b: int) -> bool:
	return _leaf.has(b) and int(_leaf[b][1]) == 2


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK_SEC
	var t0 := Time.get_ticks_usec()
	tick(clock.total_minutes())
	stat_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Один шаг: саженцы и пересмотр листвы колонн, до которых дошла очередь.
func tick(now: float) -> void:
	var n := 0
	for p: Vector3i in saplings.keys():
		update_sapling(p, now)
		n += 1
		if n >= SAPLINGS_PER_TICK:
			break
	n = 0
	for c: Vector2i in _cols.keys():
		var last: float = _cols[c]
		if last >= 0.0 and now - last < RESCAN_MINUTES:
			continue
		rescan_column(c, now)
		n += 1
		if n >= COLUMNS_PER_TICK:
			break


# --- Саженцы ---------------------------------------------------------------------------------

func _on_soil(p: Vector3i) -> bool:
	var below := world.registry.block_by_num(world.get_block(p.x, p.y - 1, p.z))
	return below != null and (below.has_tag("plantable") or below.has_tag("soil"))


## Досчитать саженец до момента now; дорос — дерево.
func update_sapling(p: Vector3i, now: float) -> void:
	var b := world.get_block(p.x, p.y, p.z)
	var e := world.get_entity(p)
	if not _sapling_tree.has(b) or e.get("type", "") != "sapling":
		saplings.erase(p)
		return
	var hours := clampf((now - float(e.get("t", now))) / 60.0, 0.0, MAX_CATCHUP_DAYS * 24.0)
	e["t"] = now
	var t: int = _sapling_tree[b]
	e["p"] = float(e.get("p", 0.0)) + Orchard.sapling_growth(_grow_days[t], hours, season_index(), _on_soil(p))
	if float(e["p"]) >= 1.0:
		grow_tree(p, t)


## Вырастить дерево вида t из саженца в p. Возвращает число записанных блоков.
func grow_tree(p: Vector3i, t: int) -> int:
	saplings.erase(p)
	var tb := world.generator.trees
	var w := WorldTreeWriter.new(world, p)
	w.set_block(p.x, p.y, p.z, 0)
	tb.build(t, p.x, p.y, p.z, GenRandom.hash3(world.world_seed, p.x, p.y, p.z, 97), w)
	var n := w.count()
	world.apply_changes(w.changes())
	world.set_entity(p, {})
	tree_grown.emit(p, tb.ids[t])
	return n


## Удобрить саженец в p: рост сразу продвигается на половину силы удобрения. true — удобрен.
func fertilize(p: Vector3i, power: float) -> bool:
	if not _sapling_tree.has(world.get_block(p.x, p.y, p.z)):
		return false
	var e := world.get_entity(p)
	if e.get("type", "") != "sapling":
		return false
	e["p"] = float(e.get("p", 0.0)) + 0.5 * power
	if float(e["p"]) >= 1.0:
		grow_tree(p, _sapling_tree[world.get_block(p.x, p.y, p.z)])
	return true


# --- Плодовая листва -------------------------------------------------------------------------

## Пересмотреть плодовую листву колонны c: смена сезона, дозревание.
func rescan_column(c: Vector2i, now: float) -> void:
	var col: ChunkColumn = world.chunks.columns.get(c)
	if col == null:
		_cols.erase(c)
		return
	var last: float = _cols.get(c, -1.0)
	_cols[c] = now
	var days := 1.0 if last < 0.0 else (now - last) / 1440.0
	var s := season_index()
	var ch := PackedInt32Array()
	var found := false
	for si in col.sections.size():
		var sec: ChunkSection = col.sections[si]
		if sec == null or sec.is_uniform():
			continue
		var any := false
		for id in _fruit_ids:
			if sec.blocks.has(id):
				any = true
				break
		if not any:
			continue
		found = true
		var blocks := sec.blocks
		var by := WorldConst.MIN_Y + si * 16
		for i in blocks.size():
			var b := blocks[i]
			if not _leaf.has(b):
				continue
			var info: Array = _leaf[b]
			var ft: Dictionary = _fruit_trees[info[0]]
			var x := c.x * 16 + (i & 15)
			var y := by + (i >> 8)
			var z := c.y * 16 + ((i >> 4) & 15)
			var h := GenRandom.unit3(world.world_seed, x, y, z, Orchard.SALT)
			var v := Orchard.next_variant(int(info[1]), s, h, int(ft["mask"]), _rng.randf(), days)
			if v != int(info[1]):
				ch.append_array([x, y, z, int(ft["blocks"][v])])
	if not found:
		# В колонне нет плодовых — до перезагрузки не смотрим (новые деревья добавят её снова).
		_cols.erase(c)
		return
	if not ch.is_empty():
		world.apply_changes(ch)


## Сбор плодов ПКМ. true — собрано.
func harvest(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	if not is_fruit_leaves(b):
		return false
	var ft: Dictionary = _fruit_trees[_leaf[b][0]]
	world.set_block(p.x, p.y, p.z, int(ft["blocks"][0]))
	var item := world.registry.item(ft["fruit"])
	if item != null and world.game_mode != &"creative":
		world.items_dropped.emit(p.x + 0.5, p.y + 0.2, p.z + 0.5, [ItemStack.create(item, _rng.randi_range(1, 2))])
	Audio.play_at("blocks/leaves_break", world.to_scene(p.x + 0.5, p.y + 0.5, p.z + 0.5))
	return true


# --- Падение срубленного дерева --------------------------------------------------------------

## Бревно сломано в p: собрать то, что держалось на нём, убрать из мира и уронить.
func fell(p: Vector3i, log_block: int, from: Vector3) -> int:
	var tf := TreeFeller.new()
	if not tf.collect(world, p, log_block, _log_leaves.get(log_block, PackedInt32Array())):
		return 0
	world.apply_changes(tf.clear_changes())
	felled += 1
	tree_felled.emit(p, tf.blocks.size())
	Audio.play_at("blocks/tree_fall", world.to_scene(p.x + 0.5, p.y + 1.0, p.z + 0.5))
	if not animate or not is_inside_tree():
		var pts := []
		for q: Vector3i in tf.blocks:
			pts.append([Vector3(q) + Vector3(0.5, 0.5, 0.5), tf.blocks[q]])
		_on_landed(pts)
		return tf.blocks.size()
	if _mesher == null:
		_mesher = GreedyMesher.create_best(world.registry)
	var pivot := Vector3(p.x + 0.5, p.y, p.z + 0.5)
	var dir := pivot - from
	var col: ChunkColumn = world.chunks.columns.get(Vector2i(p.x >> 4, p.z >> 4))
	var node := FallingTree.new()
	node.setup(world, _mesher, tf.blocks, pivot, dir, col.tints if col != null else PackedColorArray())
	node.landed.connect(_on_landed)
	world.chunks.add_child(node)
	return tf.blocks.size()


## Дерево легло: предметы из каждого блока (бревно — само, листва — палки и саженцы по шансу,
## листва с плодами — ещё и плод), собранные в кучки по ~3 блока.
func _on_landed(points: Array) -> void:
	if world.game_mode == &"creative":
		return
	var reg := world.registry
	var piles := {}   # Vector3i (кучка 3×3×3) → { id → [ItemStack, точка] }
	for pt: Array in points:
		var at: Vector3 = pt[0]
		var b: int = pt[1]
		var stacks: Array[ItemStack] = world.roll_drops(b)
		if is_fruit_leaves(b):
			var item := reg.item(_fruit_trees[_leaf[b][0]]["fruit"])
			if item != null:
				stacks.append(ItemStack.create(item, 1))
		var key := Vector3i(floori(at.x / 3.0), floori(at.y / 3.0), floori(at.z / 3.0))
		var pile: Dictionary = piles.get(key, {})
		for s: ItemStack in stacks:
			if pile.has(s.id):
				(pile[s.id][0] as ItemStack).count += s.count
			else:
				pile[s.id] = [s, at]
		piles[key] = pile
	for key: Vector3i in piles:
		for id: StringName in piles[key]:
			var s: ItemStack = piles[key][id][0]
			var at: Vector3 = piles[key][id][1]
			var out: Array[ItemStack] = []
			var def := reg.item(id)
			var mx := maxi(1, def.stack if def != null else 64)
			while s.count > mx:
				var part := s.copy()
				part.count = mx
				out.append(part)
				s.count -= mx
			out.append(s)
			world.items_dropped.emit(at.x, at.y + 0.3, at.z, out)


# --- События мира ----------------------------------------------------------------------------

func _on_block_broken(p: Vector3i, block: int, _at: Vector3) -> void:
	if _log_leaves.has(block):
		var from := Vector3(p.x + 0.5, p.y, p.z + 0.5) - Vector3(1, 0, 0)
		if player != null:
			from = Vector3(player.body.x, player.body.y, player.body.z)
		fell(p, block, from)


func _on_block_changed(p: Vector3i, old: int, new: int) -> void:
	if _sapling_tree.has(new):
		world.set_entity(p, { "type": "sapling", "tree": String(world.generator.trees.ids[_sapling_tree[new]]),
			"p": 0.0, "t": clock.total_minutes() })
		saplings[p] = true
	elif _sapling_tree.has(old):
		saplings.erase(p)
	# Под саженцем убрали почву — он выпадает.
	if _sapling_tree.has(world.get_block(p.x, p.y + 1, p.z)) and not _on_soil(p + Vector3i.UP):
		world.execute(GameAction.break_block(p + Vector3i.UP))
	if _leaf.has(new) and not _leaf.has(old):
		var c := Vector2i(p.x >> 4, p.z >> 4)
		if not _cols.has(c):
			_cols[c] = -1.0


func _on_column_loaded(c: Vector2i) -> void:
	var col: ChunkColumn = world.chunks.columns.get(c)
	if col == null:
		return
	_cols[c] = -1.0
	for key: int in col.block_entities.keys():
		var e: Dictionary = col.block_entities[key]
		if e.get("type", "") == "sapling":
			var lp := ChunkColumn.entity_pos(key)
			saplings[Vector3i(c.x * 16 + lp.x, lp.y, c.y * 16 + lp.z)] = true


func _on_column_unloading(c: Vector2i) -> void:
	_cols.erase(c)
	for p: Vector3i in saplings.keys():
		if p.x >> 4 == c.x and p.z >> 4 == c.y:
			saplings.erase(p)
