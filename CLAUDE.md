# CLAUDE.md — «Кубач»

Блочная 3D-песочница-выживание на **Godot 4.7.2 (Forward+)**, GDScript, тесты на GUT 9.7.1.
Главный источник правды — `GAME_DESIGN.md`. Перед задачей перечитай нужные разделы ТЗ.
Язык общения, комментариев и коммитов — русский.

## Правила (раздел 0 ТЗ)

1. **Один этап за сессию** (раздел 24). В конце этапа игра запускается, `scripts/check.sh` и `scripts/test.sh` зелёные, всё закоммичено.
2. **Контент — данными, не кодом.** Блоки, предметы, рецепты, биомы, мобы, блюда, квесты, навыки — в `data/*.json` (формат: `data/README.md`). Новый блок добавляется без правки движковых систем.
3. **Никаких синтезированных звуков и музыки.** Только реальные записи из `assets/audio/`. Нет файла — AudioManager молча пропускает и пишет предупреждение в лог. Недостающие звуки — в `assets/audio/MANIFEST.md`, источники и лицензии — в `assets/audio/CREDITS.md`. ИИ-генерация музыки запрещена.
4. **Текстуры:** CC0 PBR из `assets/textures/source/` или процедурный `tools/texgen/` (Python + numpy/Pillow) с детализацией: трещины, вкрапления, сколы, вариации цвета, normal, roughness. Плоская заливка с шумом не принимается.
5. **Модульность:** одна система — одна папка. Юнит-тесты GUT обязательны для генерации, освещения, воды, инвентаря и крафта.
6. После этапа обнови `CHANGELOG.md` и «Статус» в конце `GAME_DESIGN.md`.
7. **Производительность — требование** (раздел 20). Если фича роняет FPS ниже цели — переделать или убрать в настройку.
8. **Не упрощай молча.** Если что-то из ТЗ сделать нельзя — напиши почему и предложи ближайшую альтернативу. Если реализация расходится с ТЗ — сначала обнови ТЗ с пометкой «изменено, почему».

## Команды

| Команда | Что делает |
|---|---|
| `scripts/check.sh` | JSON в `data/` валиден; все `.gd` из `src/ tests/ tools/` компилируются (с автозагрузками); `Registry` грузит `data/` без ошибок. |
| `scripts/test.sh [аргументы GUT]` | Все GUT-тесты из `tests/`. Пример: `scripts/test.sh -gselect=test_registry`. JUnit-отчёт: `build/test_results.xml`. |
| `scripts/bench.sh [--strict \| --update-baseline]` | CPU-бенчмарки из `tools/bench/cases/`, сравнение с `tools/bench/baseline.json`. |
| `scripts/screenshot.sh [out.png] [аргументы игры]` | Запуск под Xvfb с программным OpenGL и сохранение кадра (визуальный смоук-тест). Пример: `scripts/screenshot.sh build/s.png --world=Тест --view=6 --camera=back --teleport=40.5,~,40.5 --f3`. |
| `scripts/build_native.sh [linux\|windows]` | Сборка C++-расширения `native/kubach_native` (godot-cpp 4.5 скачивается в `tools/`; Windows — кросс-компиляцией через zig). Готовые `.so`/`.dll` лежат в `native/bin/` и коммитятся. |
| `scripts/export_windows.sh` | `build/windows/Kubach.exe` (pck встроен) + `libkubach_native…dll` рядом. Сам скачивает шаблоны экспорта. |
| `scripts/export_linux.sh` | `build/linux/Kubach.x86_64`. |

- Godot скачивается автоматически в `tools/godot/` (в `.gitignore`) при первом запуске любого скрипта. Версия — `GODOT_VERSION` в `scripts/common.sh`. Свой бинарник: `GODOT=/путь scripts/test.sh`.
- Все запуски Godot идут через `godot_run` с таймаутом: в headless-режиме Godot при ошибке скрипта может не выйти сам.
- **Ловушка:** в режиме `godot --script file.gd` (и `--check-only`) автозагрузки (`Registry`, `EventBus`) не видны компилятору. Поэтому утилиты в `tools/` запускаются как сцены (`godot --headless --path . res://tools/.../x.tscn`), а классы, которые используют утилиты (например `ContentRegistry`), не обращаются к автозагрузкам по имени — только через `get_node_or_null("/root/...")`.
- **`check.sh`/`test.sh` всегда переимпортируют проект**: без этого новые `class_name` не попадают в кэш и скрипты «не видят» классы.
- **Packed-массивы в GDScript 4 передаются по ссылке.** Снимок для потока = ссылка на массив, который потом не меняется: `ChunkSection.set_block()` сначала заменяет массив копией. Массовые записи собирают новый массив и присваивают целиком.
- **`Vector3` — float32.** Мировые координаты (до ±15 000) и сдвиги храни в `float` (double) по отдельности или в `PackedFloat64Array`; `Vector3` — только для сценовых координат после `World.to_scene()`.
- Аргументы запуска игры (`--world`, `--seed`, `--creative`, `--view`, `--teleport=x,~,z`, `--look`, `--camera`, `--f3`, `--screenshot`, `--bench`) описаны в `src/core/game/game_launch.gd`.
- **Нативное расширение.** Горячие циклы, упёршиеся в GDScript, переносятся в `native/kubach_native/src/` (сейчас — greedy-мешер, `NativeMesher`). GDScript-версия остаётся эталоном и запасным путём: `GreedyMesher.create_best()` берёт C++, если библиотека загрузилась. **Любая правка `greedy_mesher.gd` повторяется в `native_mesher.cpp`**, иначе упадёт `test_native_mesher.gd` (сравнивает результаты побайтно). `KUBACH_NO_NATIVE=1` — принудительно GDScript.
- **Циклические ссылки RefCounted не освобождаются.** Вспомогательные объекты генератора (`CaveCarver`, `OrePlacer`, `VegetationPlacer`) не хранят генератор — получают нужные значения в `_init` или генератор параметром. Статические переменные держат только простые данные (`GameLaunch.settings` — словарь).
- Имена помощников в тестах не должны совпадать с членами `GutTest` (например, `_compare` занят).
- Каталоги с `.gdignore` (godot-cpp, сборки) не импортируются Godot и не проверяются `check.sh`.
- GUT считает любую ошибку движка (`push_error`, ошибки RegEx и т.п.) провалом теста. Ожидаемые ошибки помечай `assert_engine_error(...)` / `assert_push_error(...)`.

## Структура (раздел 23)

```
project.godot          Forward+, имя «Кубач», user://Kubach
data/                  JSON-контент; data/schemas/ — схемы категорий (см. data/README.md)
assets/                textures (source, generated), models, audio (sfx, music, ambience), fonts, shaders
src/
  core/                EventBus, Registry (registry/), perf/ (FrameTimeLogger); позже GameState, SaveSystem, Settings, Time&Season
  world/               WorldGen, Chunk, ChunkManager, Mesher, LOD, Lighting; structures/ — деревни, поселения, лагеря
  fluids/ weather/ player/ inventory/ crafting/ cooking/ farming/ fishing/
  power/ npc/ ai/ combat/ progression/ audio/
  ui/                  меню, HUD, окна (сейчас — ui/boot/ стартовый экран этапа 0)
tests/                 GUT: unit/<система>/test_*.gd, helpers/ — общие помощники тестов
tools/                 godot/ (бинарник, не в git), check/, bench/, texgen/
native/                C++ GDExtension — только если профилирование покажет узкое место
scripts/               check, test, bench, screenshot, export_*
docs/                  скриншоты и заметки
```

Автозагрузки: `EventBus` (`src/core/event_bus.gd`), `Registry` (`src/core/registry/registry.gd`, класс `ContentRegistry`), `Controls` (действия InputMap из `data/input_bindings.json`, физические клавиши), `Audio` (`src/audio/audio_manager.gd`).

Мир (этап 1): `World` (доступ к блокам, слой действий `execute(GameAction)`, floating origin) → `ChunkManager` (потоки генерации и мешинга, бюджет применения мешей, отсечение пещер) → `ChunkColumn` (36 × `ChunkSection` 16³ + карта биомов и сетка цветов). `RegionStore` + `WorldSave` — сохранения. Игрок: `Player` (узел) → `PlayerMotor` (движение) → `VoxelBody` (AABB-коллизии в double).

Генерация (этап 2, `src/world/gen/`): `TerrainGenerator` — конвейер колонны и чистые функции (`surface_info`, `biome_index_at`, `height_at`); `BiomeSource` — выбор биома по климату; `GeologySampler` — провинции и слои; `CaveCarver`, `OrePlacer`, `VegetationPlacer` + `TreeBuilder`; `ColumnWriter` — запись с отсечением по колонне; `GenRandom` — хэши, не зависящие от порядка; `WorldGenSettings` — настройки с экрана создания; `BiomePreview` — карта для экрана создания. Всё, что пересекает границу колонны (деревья, залежи, валуны), строится целиком из хэша «хозяина», а колонна пишет только свои блоки.

## Соглашения по коду

- GDScript со **статической типизацией везде** (`var x: int`, `-> void`, `:=`). Отступы — табы.
- `class_name` — для переиспользуемых классов (`BlockDef`, `ContentRegistry`). Имя автозагрузки не совпадает с `class_name`.
- Документирующие комментарии `##` на русском у классов и публичных методов.
- Системы общаются через сигналы `EventBus`, а не прямыми ссылками друг на друга. Команды игрока идут через слой действий (задел под мультиплеер, раздел 22).
- Горячие циклы (шум, мешинг, вода, свет) — в `WorkerThreadPool`, на типизированных `Packed*Array`. Главный поток только применяет готовые результаты с бюджетом N мс на кадр. Медленно — переносим в `native/`.
- Блоки в чанках — `uint16` (числовой ID из `Registry`). Числовые ID действуют только в пределах запуска. На диск всегда пишется палитра строковых ID.
- Новая система → своя папка в `src/`, свои тесты в `tests/unit/<система>/`, свой бенчмарк в `tools/bench/cases/`, если она в горячем пути.

## Как проверяется производительность без видеокарты

В облаке нет GPU: Vulkan недоступен, а Xvfb даёт только программный OpenGL (llvmpipe). Поэтому FPS в облаке не измеряется вообще — любые цифры там ничего не значат. Производительность делится на два слоя.

**1. CPU-часть — меряю в облаке, на каждом этапе.**
- `scripts/bench.sh` гоняет кейсы из `tools/bench/cases/*.gd`. Каждый кейс — класс с `name`, `iterations`, `setup()`, `run()`, `teardown()`. Берётся медиана, результат пишется в `build/bench/cpu_bench.json`.
- Сравнение с `tools/bench/baseline.json`: если медиана выросла больше чем на 25%, выводится предупреждение, а с `--strict` скрипт падает. Эталон снят на облачном CPU (4 потока), поэтому сравнивать можно только облако с облаком.
- По мере этапов сюда добавляются: генерация колонны чанка, greedy-мешинг секции, распространение света, тик водяной симуляции, расчёт электросети, тик ИИ на N мобов.
- Бюджеты (для 6-ядерного CPU из раздела 20, в облаке пересчитываю пропорционально): мешинг секции 16³ — < 2 мс в одном потоке (C++: ~0,3 мс); генерация колонны — < 10 мс (сейчас ~27 мс в облаке на GDScript — кандидат в C++ на этапе оптимизации); применение готовых мешей в главном потоке — ≤ 3 мс на кадр. Внутриигровые счётчики (F3, этап 1) показывают очередь чанков, время генерации и мешинга.
- Сложность алгоритмов проверяю тестами: число вершин и граней после greedy-мешинга, количество draw calls на чанк (по числу поверхностей меша), размер очередей.

**2. GPU-часть — меряешь ты на ПК, по бенчмарк-логам.**
- `FrameTimeLogger` (`src/core/perf/frame_time_logger.gd`) пишет frametime каждого кадра в CSV, а сводку — в JSON: avg FPS, 1% low, p50/p95/p99, число фризов > 33 мс. Раз в 0,5 с туда же снимаются счётчики draw calls, primitives, объектов, видеопамяти. Файлы ложатся в `%APPDATA%\Kubach\bench\` (Windows) или `~/.local/share/Kubach/bench/` (Linux).
- Запуск: `Kubach.exe -- --bench=60 --view=12`. Это временный мир с сидом `bench`: камера летит на восток по прямой со скоростью полёта (10,9 м/с) на высоте 28 блоков над рельефом. Сохранение не создаётся. Прогоны сравнимы между собой. На этапе 2 маршрут пройдёт через тайгу, пещеру и воду.
- Сводку JSON вставляешь в промт «Проверка производительности». По ней я ищу узкое место: draw calls → батчинг или LOD; primitives → LOD или децимация; process_ms → CPU-логика; провалы 1% low → подгрузка чанков в главном потоке.
- `scripts/screenshot.sh` в облаке проверяет только то, что сцена собирается и рисуется (через OpenGL 3, без Forward+-эффектов). Это смоук-тест, а не замер.
