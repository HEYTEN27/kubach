# Аудио: что нужно и что уже есть

Сюда кладутся только **настоящие записи** (CC0, лицензионные библиотеки или собственные). Синтез в коде и ИИ-генерация запрещены (разделы 0, 17, 18 ТЗ).
Каждый добавленный файл вносится в `CREDITS.md`: источник, автор, лицензия, ссылка.

**Как подключается.** AudioManager (`src/audio/audio_manager.gd`, автозагрузка `Audio`) ищет вариации
`res://assets/audio/sfx/<ключ>_01.ogg` … `_08.ogg` (или `.wav`) и проигрывает случайную со сдвигом
высоты ±5%. Если нет ни одной вариации, звук пропускается, а в лог один раз пишется предупреждение.
Значит, достаточно положить файлы с правильными именами, код менять не нужно.

Формат: `.ogg` (Vorbis, 44,1 или 48 кГц), моно для 3D-звуков. Короткие одиночные звуки допустимы в `.wav`.
Статус: ⬜ нет файла · ✅ есть.

## Подключено на этапе 1

Группы `<группа>` берутся из поля `sounds` в `data/blocks*.json`:
`stone` (все породы, руды, кораллы), `dirt` (почвы, глина, торф), `grass` (дернина, растения, мох),
`sand`, `gravel`, `wood` (брёвна, бамбук, гигантские грибы), `leaves` (листва и хвоя),
`water`, `lava`, `snow` (снег, снежный покров), `glass` (лёд), `metal` (железный сундук, этап 4).

| Ключ (файлы `<ключ>_01..06.ogg`) | Когда звучит | Статус |
|---|---|---|
| `footsteps/stone_`, `footsteps/dirt_`, `footsteps/grass_`, `footsteps/sand_`, `footsteps/gravel_`, `footsteps/wood_`, `footsteps/leaves_`, `footsteps/water_`, `footsteps/lava_`, `footsteps/snow_`, `footsteps/glass_`, `footsteps/metal_` | шаг игрока каждые 2 блока (4–6 вариаций) | ⬜ |
| `blocks/stone_break_`, `blocks/dirt_break_`, `blocks/grass_break_`, `blocks/sand_break_`, `blocks/gravel_break_`, `blocks/wood_break_`, `blocks/leaves_break_`, `blocks/water_break_`, `blocks/lava_break_`, `blocks/snow_break_`, `blocks/glass_break_`, `blocks/metal_break_` | блок сломан (3–4 вариации) | ⬜ |
| `blocks/stone_place_`, `blocks/dirt_place_`, `blocks/grass_place_`, `blocks/sand_place_`, `blocks/gravel_place_`, `blocks/wood_place_`, `blocks/leaves_place_`, `blocks/water_place_`, `blocks/lava_place_`, `blocks/snow_place_`, `blocks/glass_place_`, `blocks/metal_place_` | блок поставлен (3 вариации) | ⬜ |

## Подключено на этапе 4

Звуки интерфейса идут на шину UI (без позиции), звуки хранилищ — в точке блока.

| Ключ (файлы `<ключ>_01..NN.ogg`) | Когда звучит | Статус |
|---|---|---|
| `ui/inventory_open_`, `ui/inventory_close_` | открыть/закрыть инвентарь (шорох ткани, 2 вариации) | ⬜ |
| `ui/pickup_` | подобран предмет (короткий мягкий щелчок, 3 вариации) | ⬜ |
| `ui/click_` | кнопка меню и настроек (деревянный щелчок, 2 вариации) | ⬜ |
| `containers/chest_open_`, `containers/dresser_open_`, `containers/barrel_open_`, `containers/crate_open_` | открыть хранилище (скрип петель / выдвинутый ящик / деревянная крышка) | ⬜ |

## Будет подключено позже

| Ключ | Этап |
|---|---|
| `blocks/<группа>_dig_01..04` — удары во время ломания | 6 (инструменты) |
| Окружение по биомам, погода, музыка | 2, 7, 16 |
