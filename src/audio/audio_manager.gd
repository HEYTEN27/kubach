extends Node
## Автозагрузка `Audio` (раздел 17 ТЗ). Только настоящие записи из assets/audio/ — никакого синтеза.
##
## Звук задаётся ключом "папка/имя" (например "footsteps/grass"); файлы — вариации
## res://assets/audio/sfx/<ключ>_01.ogg … _08.ogg (или .wav). Нет ни одного файла — звук
## пропускается, а в лог один раз пишется предупреждение со ссылкой на MANIFEST.md.
## Полноценный звук (окружение, музыка, реверберация) — этап 16.

const SFX_ROOT := "res://assets/audio/sfx"
const MAX_VARIANTS := 8
const POOL_SIZE := 16
const PITCH_SPREAD := 0.05
const LOOP_FADE_DB_PER_S := 30.0

var _cache := {}    # ключ -> Array[AudioStream]
var _warned := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ui: AudioStreamPlayer
var _ambient: AudioStreamPlayer
## Зацикленные фоны (погода, этап 7): канал → { player, key, target }.
var _loops := {}


func _ready() -> void:
	_ui = AudioStreamPlayer.new()
	_ui.bus = &"UI"
	add_child(_ui)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = &"Ambience"
	_ambient.max_polyphony = 3
	add_child(_ambient)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 6.0
		p.max_distance = 48.0
		add_child(p)
		_pool.append(p)
	var bus := get_node_or_null(^"/root/EventBus")
	if bus:
		bus.block_broken.connect(func(_p: Vector3i, block: int, at: Vector3) -> void: _block_sound(block, "break", at))
		bus.block_placed.connect(func(_p: Vector3i, block: int, at: Vector3) -> void: _block_sound(block, "place", at))
		bus.player_step.connect(func(group: StringName, at: Vector3) -> void: play_at("footsteps/%s" % group, at))


## Звук интерфейса (не в пространстве, шина UI). false — файлов нет.
func play_ui(key: String, volume_db: float = 0.0) -> bool:
	var streams := streams_for(key)
	if streams.is_empty():
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Audio: нет файлов для '%s' (%s/%s_01.ogg …) — см. assets/audio/MANIFEST.md" % [key, SFX_ROOT, key])
		return false
	_ui.stream = streams[randi() % streams.size()]
	_ui.volume_db = volume_db
	_ui.play()
	return true


## Проиграть случайную вариацию звука в точке сцены. false — файлов нет.
func play_at(key: String, at: Vector3, volume_db: float = 0.0) -> bool:
	var streams := streams_for(key)
	if streams.is_empty():
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Audio: нет файлов для '%s' (%s/%s_01.ogg …) — см. assets/audio/MANIFEST.md" % [key, SFX_ROOT, key])
		return false
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = streams[randi() % streams.size()]
	p.pitch_scale = 1.0 + randf_range(-PITCH_SPREAD, PITCH_SPREAD)
	p.volume_db = volume_db
	p.global_position = at
	p.play()
	return true


## Звук окружения без позиции (гром, далёкие события) на шине Ambience. false — файлов нет.
func play_ambient(key: String, volume_db: float = 0.0) -> bool:
	var streams := streams_for(key)
	if streams.is_empty():
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Audio: нет файлов для '%s' (%s/%s_01.ogg …) — см. assets/audio/MANIFEST.md" % [key, SFX_ROOT, key])
		return false
	_ambient.stream = streams[randi() % streams.size()]
	_ambient.pitch_scale = 1.0 + randf_range(-PITCH_SPREAD, PITCH_SPREAD)
	_ambient.volume_db = volume_db
	_ambient.play()
	return true


## Зацикленный фон на канале channel (шина Ambience): key — звук ("" — выключить), громкость
## меняется плавно. Нет файлов — молча (одно предупреждение в лог), канал выключается.
func set_loop(channel: StringName, key: String, volume_db: float = 0.0) -> void:
	var l: Dictionary = _loops.get(channel, {})
	if l.is_empty():
		var p := AudioStreamPlayer.new()
		p.bus = &"Ambience"
		p.volume_db = -60.0
		add_child(p)
		l = { "player": p, "key": "", "target": -60.0 }
		_loops[channel] = l
	var player: AudioStreamPlayer = l["player"]
	if key != String(l["key"]):
		l["key"] = key
		var streams := streams_for(key) if key != "" else []
		if streams.is_empty():
			if key != "" and not _warned.has(key):
				_warned[key] = true
				push_warning("Audio: нет файлов для '%s' (%s/%s_01.ogg …) — см. assets/audio/MANIFEST.md" % [key, SFX_ROOT, key])
			player.stop()
			player.stream = null
		else:
			var st: AudioStream = streams[randi() % streams.size()]
			if "loop" in st:
				st.set(&"loop", true)
			player.stream = st
			player.volume_db = -60.0
			player.play()
	l["target"] = volume_db if key != "" else -60.0


## Есть ли файлы для звука (для выбора «под крышей» / «снаружи»).
func has_sound(key: String) -> bool:
	return not streams_for(key).is_empty()


func _process(delta: float) -> void:
	for ch: StringName in _loops:
		var l: Dictionary = _loops[ch]
		var p: AudioStreamPlayer = l["player"]
		if p.stream == null:
			continue
		p.volume_db = move_toward(p.volume_db, float(l["target"]), LOOP_FADE_DB_PER_S * delta)
		if not p.playing and float(l["target"]) > -59.0:
			p.play()


func streams_for(key: String) -> Array:
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	for i in range(1, MAX_VARIANTS + 1):
		for ext in ["ogg", "wav"]:
			var path := "%s/%s_%02d.%s" % [SFX_ROOT, key, i, ext]
			if ResourceLoader.exists(path):
				out.append(load(path))
	_cache[key] = out
	return out


func _block_sound(block: int, action: String, at: Vector3) -> void:
	var reg := get_node_or_null(^"/root/Registry") as ContentRegistry
	var def := reg.block_by_num(block) if reg else null
	if def != null and def.sounds != &"none":
		play_at("blocks/%s_%s" % [def.sounds, action], at)
