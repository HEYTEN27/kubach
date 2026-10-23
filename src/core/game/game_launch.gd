class_name GameLaunch
extends RefCounted
## Что запускать в игровой сцене. Заполняется стартовым экраном или аргументами командной строки.
##
## Аргументы (после `--`):
##   --world=<имя>        открыть мир с таким именем или создать новый;
##   --seed=<текст>       сид для нового мира;
##   --creative           творческий режим для нового мира;
##   --view=<колонн>      дальность прорисовки (4–32);
##   --teleport=x,y,z     переместить игрока (мировые координаты; y = ~ — на поверхность);
##   --look=рыск,тангаж   направление взгляда в градусах;
##   --camera=first|back|front
##   --f3                 сразу показать отладочный экран;
##   --screenshot=<png>   дождаться загрузки, сохранить кадр и выйти;
##   --bench=<сек>        бенчмарк: временный мир, полёт по прямой, лог frametime, выход.

static var folder := ""
static var new_world_name := ""
static var seed_text := ""
static var game_mode: StringName = &"survival"
static var view_distance := 12
static var teleport := PackedFloat64Array()
static var look := Vector2(INF, INF)
static var camera := ""
static var show_debug := false
static var screenshot_path := ""
static var bench_seconds := 0.0


static func reset() -> void:
	folder = ""
	new_world_name = ""
	seed_text = ""
	game_mode = &"survival"
	teleport = PackedFloat64Array()
	look = Vector2(INF, INF)
	camera = ""
	show_debug = false
	screenshot_path = ""
	bench_seconds = 0.0


## Разбирает аргументы командной строки. true — аргументы требуют сразу запустить игру.
static func parse_args(args: PackedStringArray) -> bool:
	var start := false
	for arg in args:
		var key := arg.get_slice("=", 0)
		var value := arg.substr(key.length() + 1)
		match key:
			"--world":
				start = true
				new_world_name = value
				for w in WorldSave.list_worlds():
					if w["name"] == value:
						folder = w["folder"]
			"--seed":
				seed_text = value
			"--creative":
				game_mode = &"creative"
			"--view":
				view_distance = clampi(value.to_int(), 4, 32)
			"--teleport":
				var p := value.split(",")
				if p.size() == 3:
					teleport = PackedFloat64Array([p[0].to_float(), NAN if p[1] == "~" else p[1].to_float(), p[2].to_float()])
			"--look":
				var l := value.split_floats(",")
				if l.size() == 2:
					look = Vector2(l[0], l[1])
			"--camera":
				camera = value
			"--f3":
				show_debug = true
			"--screenshot":
				screenshot_path = value
			"--bench":
				start = true
				bench_seconds = maxf(5.0, value.to_float())
	return start
