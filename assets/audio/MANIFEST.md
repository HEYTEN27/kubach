# Аудио: что нужно и что уже есть

Сюда кладутся только **настоящие записи** (CC0, лицензионные библиотеки или собственные). Синтез в коде и ИИ-генерация запрещены (разделы 0, 17, 18 ТЗ).
Каждый добавленный файл вносится в `CREDITS.md`: источник, автор, лицензия, ссылка.

Формат: `.ogg` (Vorbis, 44.1/48 кГц). Короткие одиночные звуки допустимы в `.wav`. Имена — `snake_case`, вариации — `_01`, `_02`, …
Статус: ⬜ нет файла · ✅ есть.

## Шаги (assets/audio/sfx/footsteps/) — 4–6 вариаций каждого
Группы совпадают с полем `sounds` в `data/blocks.json`.

| Файл | Статус | Используется |
|---|---|---|
| `footsteps/stone_01..06.ogg` | ⬜ | granite, limestone, bedrock |
| `footsteps/dirt_01..06.ogg` | ⬜ | loam |
| `footsteps/grass_01..06.ogg` | ⬜ | turf |
| `footsteps/sand_01..06.ogg` | ⬜ | sand |
| `footsteps/gravel_01..06.ogg` | ⬜ | gravel |
| `footsteps/wood_01..06.ogg` | ⬜ | spruce_log |
| `footsteps/leaves_01..06.ogg` | ⬜ | spruce_needles |
| `footsteps/water_01..06.ogg` | ⬜ | water (мелководье) |

## Ломание и установка блоков (assets/audio/sfx/blocks/)

| Файл | Статус |
|---|---|
| `blocks/{stone,dirt,grass,sand,gravel,wood,leaves}_dig_01..04.ogg` | ⬜ |
| `blocks/{stone,dirt,grass,sand,gravel,wood,leaves}_break_01..03.ogg` | ⬜ |
| `blocks/{stone,dirt,grass,sand,gravel,wood,leaves}_place_01..03.ogg` | ⬜ |

Остальные группы (окружение, погода, станции, животные, музыка) добавляются в этот список на этапах, где появляются их хуки.
