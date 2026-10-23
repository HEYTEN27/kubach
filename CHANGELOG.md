# CHANGELOG

## [0.0.1] — 2026-10-23 — Этап 0: каркас проекта

### Добавлено
- Проект Godot 4.7.2 (Forward+, запасной OpenGL 3): имя «Кубач», каталог сохранений `user://` → `Kubach`, иконка, стартовый экран `src/ui/boot/`.
- `CLAUDE.md`: правила проекта, структура, команды, методика проверки производительности без видеокарты.
- Автозагрузка `EventBus` — шина сигналов.
- Автозагрузка `Registry` (`ContentRegistry`): загрузка `data/`, расширения в `data/<категория>/`, проверка по схемам (`SchemaValidator`), значения по умолчанию, отложенная проверка ссылок, понятные ошибки с файлом и полем. Для блоков — `BlockDef`, числовые ID (0 — воздух) и плоские массивы `block_solid`, `block_opaque`, `block_light_emission`, `block_light_filter`.
- `data/schemas/blocks.json` и 10 блоков в `data/blocks.json`.
- Скрипты: `scripts/check.sh`, `test.sh`, `bench.sh`, `screenshot.sh`, `export_windows.sh`, `export_linux.sh`. Godot и шаблоны экспорта скачиваются автоматически, все запуски идут с таймаутом.
- GUT 9.7.1 (`addons/gut`), 52 теста: реестр на настоящих данных, 24 сценария ошибок данных, валидатор схем, сводка frametime, настройки проекта.
- `FrameTimeLogger` (режим `-- --bench=<сек>`): CSV и JSON-сводка frametime и счётчиков рендера. CPU-бенчмарки `tools/bench/` с эталоном и порогом регрессии 25%.
- Режим `-- --screenshot=<файл>` для визуальных смоук-тестов.
- Git LFS для бинарных ассетов, `assets/audio/MANIFEST.md`, `assets/audio/CREDITS.md`.
