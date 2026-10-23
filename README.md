# Кубач

Блочная 3D-песочница про выживание: тайга, четыре сезона, вода, ремесло без сетки 3×3, электричество. Движок — Godot 4.7 (Forward+).

- Полное ТЗ: [GAME_DESIGN.md](GAME_DESIGN.md), статус — в его конце.
- Правила для разработчика и команды: [CLAUDE.md](CLAUDE.md).
- Промты по этапам: [docs/PROMPTS.md](docs/PROMPTS.md).
- История изменений: [CHANGELOG.md](CHANGELOG.md).

## Запуск на ПК

1. Установи [Git LFS](https://git-lfs.com) и клонируй репозиторий (`git lfs install`, затем `git clone ...`).
2. Скачай [Godot 4.7.2-stable](https://godotengine.org/download/archive/4.7.2-stable/) (обычная версия, не .NET).
3. Открой `project.godot` в Godot и нажми F5. Или собери `Kubach.exe` через «Проект → Экспорт → Windows Desktop».

Бенчмарк: `Kubach.exe -- --bench=60`. Отчёт появится в `%APPDATA%\Kubach\bench\`.

## Команды (Linux / облако)

```
scripts/check.sh            # проверка скриптов и данных
scripts/test.sh             # GUT-тесты
scripts/bench.sh            # CPU-бенчмарки
scripts/export_windows.sh   # build/windows/Kubach.exe
```
