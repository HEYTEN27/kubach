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
| `scripts/screenshot.sh [out.png] [аргументы игры]` | Запуск под Xvfb с программным OpenGL и сохранение кадра (визуальный смоук-тест, 1280×720, ~4 мин). Пример: `scripts/screenshot.sh build/s.png --world=Тест --view=6 --camera=back --teleport=40.5,~,40.5 --f3`. `SHOT_SIZE=1920x1080 SHOT_TIMEOUT=400` — крупнее. |
| `scripts/gallery.sh [out.png] [--blocks=a,b]` | Ряд блоков с шейдерами этапа 3 — быстрый (секунды) визуальный тест текстур и материалов. |
| `python3 tools/texgen/texgen.py [--only a,b] [--size 128]` | Перерисовать текстуры блоков (атласы `assets/textures/generated/`, превью `docs/textures_preview.png`) и иконки предметов. Нужно после добавления блока с новым набором текстур или нового предмета. ~90 с. |
| `python3 tools/texgen/icons.py` | Только иконки предметов (`items_icons.png` + `.json`): блоки — изометрия из атласа, предметы — по полю `icon` в `data/items.json`. |
| `scripts/build_native.sh [linux\|windows]` | Сборка C++-расширения `native/kubach_native` (godot-cpp 4.5 скачивается в `tools/`; Windows — кросс-компиляцией через zig). Готовые `.so`/`.dll` лежат в `native/bin/` и коммитятся. |
| `scripts/export_windows.sh` | `build/windows/Kubach.exe` (pck встроен) + `libkubach_native…dll` рядом. Сам скачивает шаблоны экспорта. |
| `scripts/export_linux.sh` | `build/linux/Kubach.x86_64`. |

- Godot скачивается автоматически в `tools/godot/` (в `.gitignore`) при первом запуске любого скрипта. Версия — `GODOT_VERSION` в `scripts/common.sh`. Свой бинарник: `GODOT=/путь scripts/test.sh`.
- Все запуски Godot идут через `godot_run` с таймаутом: в headless-режиме Godot при ошибке скрипта может не выйти сам.
- **Ловушка:** в режиме `godot --script file.gd` (и `--check-only`) автозагрузки (`Registry`, `EventBus`) не видны компилятору. Поэтому утилиты в `tools/` запускаются как сцены (`godot --headless --path . res://tools/.../x.tscn`), а классы, которые используют утилиты (например `ContentRegistry`), не обращаются к автозагрузкам по имени — только через `get_node_or_null("/root/...")`.
- **`check.sh`/`test.sh` всегда переимпортируют проект**: без этого новые `class_name` не попадают в кэш и скрипты «не видят» классы.
- **Packed-массивы в GDScript 4 передаются по ссылке.** Снимок для потока = ссылка на массив, который потом не меняется: `ChunkSection.set_block()` сначала заменяет массив копией. Массовые записи собирают новый массив и присваивают целиком.
- **`Vector3` — float32.** Мировые координаты (до ±15 000) и сдвиги храни в `float` (double) по отдельности или в `PackedFloat64Array`; `Vector3` — только для сценовых координат после `World.to_scene()`.
- Аргументы запуска игры (`--world`, `--seed`, `--creative`, `--view`, `--preset`, `--teleport=x,~,z`, `--look`, `--camera`, `--f3`, `--screenshot`, `--bench`, `--open=inventory|chest`) описаны в `src/core/game/game_launch.gd`; меню — `--menu=load|settings|credits|character` (`src/ui/boot/boot.gd`).
- **Нативное расширение.** Горячие циклы, упёршиеся в GDScript, переносятся в `native/kubach_native/src/` (сейчас — greedy-мешер `NativeMesher` и свет `NativeLight`). GDScript-версии остаются эталоном: `GreedyMesher.create_best()` / `VoxelLight.create_best()` берут C++, если библиотека загрузилась. **Любая правка `greedy_mesher.gd` повторяется в `native_mesher.cpp`, правка `voxel_light.gd` — в `native_light.cpp`**, иначе упадут `test_native_mesher.gd` / `test_voxel_light.gd` (сравнивают побайтно). `KUBACH_NO_NATIVE=1` — принудительно GDScript (свет тогда выключается: на GDScript он идёт секунды на колонну). После правки C++ — `scripts/build_native.sh` (обе платформы) и закоммитить `native/bin/`.
- **Текстуры блоков** — атласы `CompressedTexture2DArray`: это `TextureLayered`, **не** `Texture2DArray` (`load(...) as Texture2DArray` даёт null). Новый набор текстур в `data/blocks*.json` → `texgen.py`, иначе `test_block_textures` упадёт.
- **Шейдеры:** варинги можно писать только в `vertex()`/`fragment()` — общая часть вершинного шейдера блоков сделана макросом `KB_VERTEX_COMMON`, функции получают значения параметрами. `instance uniform` не годится для секций: буфер ограничен 4096 экземплярами — свет секции идёт обычным uniform в кэше материалов (`BlockMaterials.for_const`). В `check.sh` шейдеры не компилируются (headless без рендера) — проверяй `scripts/gallery.sh`.
- **Пул потоков:** генерация колонны на GDScript почти не ускоряется от потоков (общие RefCounted), поэтому её задачи ставятся с высоким приоритетом, а мешинг и свет — обычными. Иначе загрузка мира ждёт генерацию в очереди за светом.
- **Циклические ссылки RefCounted не освобождаются.** Вспомогательные объекты генератора (`CaveCarver`, `OrePlacer`, `VegetationPlacer`) не хранят генератор — получают нужные значения в `_init` или генератор параметром. Статические переменные держат только простые данные (`GameLaunch.settings` — словарь).
- Имена помощников в тестах не должны совпадать с членами `GutTest` (например, `_compare` занят). Методы узлов не называй `_set`/`_get` — это виртуальные методы Object.
- **Лямбды в connect() держат self.** Подписка RefCounted-объекта на сигнал своего же поля через лямбду — цикл, объект не освободится. Подключай методы (`inv.changed.connect(_on_changed)`).
- **Валидатор проверяет и значения по умолчанию.** У объекта-поля с `default: {}` не может быть `required`-полей внутри (иначе ошибка на каждой записи) — либо убери `default`, либо дай вложенным полям значения по умолчанию.
- `get_node_or_null("/root/...")` у узла вне дерева — ошибка движка; в таких местах сначала `is_inside_tree()`.
- Каталоги с `.gdignore` (godot-cpp, сборки) не импортируются Godot и не проверяются `check.sh`.
- GUT считает любую ошибку движка (`push_error`, ошибки RegEx и т.п.) провалом теста. Ожидаемые ошибки помечай `assert_engine_error(...)` / `assert_push_error(...)`.

## Структура (раздел 23)

```
project.godot          Forward+, имя «Кубач», user://Kubach
data/                  JSON-контент; data/schemas/ — схемы категорий (см. data/README.md)
assets/                textures (source, generated), models, audio (sfx, music, ambience), fonts, shaders
src/
  core/                EventBus, Registry (registry/), Settings (settings/), perf/ (FrameTimeLogger); позже GameState, Time&Season
  world/               ChunkManager, gen/, mesh/, light/ (VoxelLight), render/ (текстуры, шейдеры, трава), lod/ (FarTerrain), save/; structures/ — позже
  graphics/            GraphicsRig: небо, солнце, тени, туман, SSAO/SSIL, glow, AgX, автоэкспозиция, пресеты
  fluids/ weather/ player/ inventory/ crafting/ cooking/ farming/ fishing/
  power/ npc/ ai/ combat/ progression/ audio/
  inventory/           ItemStack, Inventory, PlayerInventory, InventoryOps (клики окна), DroppedItems, ItemIcons
  ui/                  boot/ (главное меню), world_create/, character/, inventory/ (окно, ячейка, подсказка),
                       settings/ (экран настроек), hud/, pause/, common/ (3D-превью персонажа), theme/ (тема, экранный фильтр)
tests/                 GUT: unit/<система>/test_*.gd, helpers/ — общие помощники тестов
tools/                 godot/ (бинарник, не в git), check/, bench/, texgen/
native/                C++ GDExtension — только если профилирование покажет узкое место
scripts/               check, test, bench, screenshot, export_*
docs/                  скриншоты и заметки
```

Автозагрузки (порядок важен): `EventBus` (`src/core/event_bus.gd`), `Registry` (`src/core/registry/registry.gd`, класс `ContentRegistry`), `Settings` (`src/core/settings/settings.gd`, класс `GameSettings`: все настройки из `data/settings.json`, пресет графики из `data/graphics_presets.json`, переназначенные клавиши; `user://settings.cfg`; применяет окно, звук, масштаб и тему UI, экранный фильтр), `Controls` (действия InputMap из `data/input_bindings.json` + переназначения игрока; клавиатура по физическим клавишам, мышь, геймпад), `Audio` (`src/audio/audio_manager.gd`, шины SFX/UI/Music/Ambience/Voice).

Инвентарь (этап 4): предметы — `Registry.item(id)` (`ItemDef`): блоки с `item: true` + `data/items.json`. `ItemStack` (id, count, data: прочность, свежесть, цвет, содержимое рюкзака; стопки складываются только при равных data). `PlayerInventory` — хотбар 9, основной 27, рюкзак (размер и содержимое — у надетого рюкзака), 9 слотов экипировки. Клики окна — `InventoryOps` через `InventoryAction` (слой действий). Хранилища — блоки с `container`; содержимое в `ChunkColumn.block_entities` (region-формат колонны 2), открытый инвентарь — `World.get_container()`. Выпавшее — `World.items_dropped` → `DroppedItems`. Модель персонажа — `CharacterModel` по `data/hairstyles.json`, `beards.json`, `face_parts.json`, `face_presets.json`, `body_types.json`, `palettes.json`; экипировка видна по полю `model` предметов. `world.json` формата 2: инвентарь, внешность, предметы на земле; `WorldSave.migrate()` поднимает старые.

Мир (этап 1): `World` (доступ к блокам, слой действий `execute(GameAction)`, floating origin) → `ChunkManager` (потоки генерации и мешинга, бюджет применения мешей, отсечение пещер) → `ChunkColumn` (36 × `ChunkSection` 16³ + карта биомов и сетка цветов). `RegionStore` + `WorldSave` — сохранения. Игрок: `Player` (узел) → `PlayerMotor` (движение) → `VoxelBody` (AABB-коллизии в double).

Графика (этап 3): `tools/texgen` → атласы albedo/normal/ORM (`Texture2DArray`, 553 слоя 128²) + `blocks_manifest.json`. `BlockTextures` строит таблицу «блок × грань → слой, вариантов, поворот» (текстура `block_info`), `BlockMaterials` — материалы 4 поверхностей мешера (`opaque`, `cutout`, `transparent`, `plants`). Вершина несёт UV в блоках, ID блока в UV2.x, вес ветра в UV2.y, множитель тонирования биомом в COLOR (÷2). Вариант и поворот текстуры — хэш мировой клетки в шейдере (глобальный uniform `world_origin`), поэтому greedy-слияние не страдает. Свет: `VoxelLight`/`NativeLight` по области 3×3 колонны → на секцию `Color` или 3D-текстура 18³ (срезы по Y, в шейдере `p.xzy`). Колонна мешится только после света (нужны все 8 соседей). `GrassField` — MultiMesh-трава, `FarTerrain` — LOD-плитки 64² из чистых функций генератора, `GraphicsRig` — окружение.

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
- Бюджеты (для 6-ядерного CPU из раздела 20, в облаке пересчитываю пропорционально): мешинг секции 16³ — < 2 мс в одном потоке (C++: ~0,3 мс); генерация колонны — < 10 мс (сейчас ~27 мс в облаке на GDScript — кандидат в C++ на этапе оптимизации); свет колонны (C++, область 3×3) — ~14 мс в облаке; LOD-плитка 64² с шагом 4 — ~26 мс (GDScript, в потоке); применение готовых мешей и света в главном потоке — ≤ 3 мс на кадр. Внутриигровые счётчики (F3, этап 1) показывают очередь чанков, время генерации и мешинга.
- Сложность алгоритмов проверяю тестами: число вершин и граней после greedy-мешинга, количество draw calls на чанк (по числу поверхностей меша), размер очередей.

**2. GPU-часть — меряешь ты на ПК, по бенчмарк-логам.**
- `FrameTimeLogger` (`src/core/perf/frame_time_logger.gd`) пишет frametime каждого кадра в CSV, а сводку — в JSON: avg FPS, 1% low, p50/p95/p99, число фризов > 33 мс. Раз в 0,5 с туда же снимаются счётчики draw calls, primitives, объектов, видеопамяти. Файлы ложатся в `%APPDATA%\Kubach\bench\` (Windows) или `~/.local/share/Kubach/bench/` (Linux).
- Запуск: `Kubach.exe -- --bench=60 --view=12`. Это временный мир с сидом `bench`: камера летит на восток по прямой со скоростью полёта (10,9 м/с) на высоте 28 блоков над рельефом. Сохранение не создаётся. Прогоны сравнимы между собой. На этапе 2 маршрут пройдёт через тайгу, пещеру и воду.
- Сводку JSON вставляешь в промт «Проверка производительности». По ней я ищу узкое место: draw calls → батчинг или LOD; primitives → LOD или децимация; process_ms → CPU-логика; провалы 1% low → подгрузка чанков в главном потоке.
- `scripts/screenshot.sh` в облаке проверяет только то, что сцена собирается и рисуется (через OpenGL 3, без Forward+-эффектов). Это смоук-тест, а не замер.
