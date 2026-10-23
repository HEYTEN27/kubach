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

var _cache := {}    # ключ -> Array[AudioStream]
var _warned := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Master"
		p.unit_size = 6.0
		p.max_distance = 48.0
		add_child(p)
		_pool.append(p)
	var bus := get_node_or_null(^"/root/EventBus")
	if bus:
		bus.block_broken.connect(func(_p: Vector3i, block: int, at: Vector3) -> void: _block_sound(block, "break", at))
		bus.block_placed.connect(func(_p: Vector3i, block: int, at: Vector3) -> void: _block_sound(block, "place", at))
		bus.player_step.connect(func(group: StringName, at: Vector3) -> void: play_at("footsteps/%s" % group, at))


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
