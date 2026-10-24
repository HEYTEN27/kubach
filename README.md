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
   Рядом с `Kubach.exe` должна лежать `libkubach_native.windows.template_release.x86_64.dll` — это быстрый C++-мешер
   (готовая библиотека уже в `native/bin/`; без неё игра работает, но мир подгружается в разы медленнее).

Бенчмарк: `Kubach.exe -- --bench=60 --view=12`. Отчёт появится в `%APPDATA%\Kubach\bench\`.

## Управление (этап 1)

| Клавиша | Действие |
|---|---|
| W A S D | ходьба (работает и на русской раскладке) |
| Пробел | прыжок; в творческом режиме двойное нажатие включает полёт, удержание — вверх |
| Ctrl | бег |
| Shift | присесть (не упадёшь с края); в полёте — вниз |
| ЛКМ (удерживать) | ломать блок |
| ПКМ | поставить блок |
| СКМ | взять блок под прицелом в палитру |
| 1–9, колесо | выбор блока |
| F5 | вид: от первого лица → из-за плеча → спереди |
| F3 | отладочный экран |
| F4 | выживание ↔ творческий (отладка) |
| Esc | пауза, сохранение, выход |

## Команды (Linux / облако)

```
scripts/check.sh            # проверка скриптов и данных
scripts/test.sh             # GUT-тесты
scripts/bench.sh            # CPU-бенчмарки
scripts/build_native.sh     # пересобрать C++-расширение (Linux и Windows)
scripts/export_windows.sh   # build/windows/Kubach.exe + dll
```
