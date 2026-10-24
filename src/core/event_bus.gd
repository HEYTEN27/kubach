extends Node
## Глобальная шина событий (автозагрузка `EventBus`).
##
## Системы не ссылаются друг на друга напрямую: они испускают и слушают сигналы здесь.
## Добавляй сигнал сюда, только если у него больше одного независимого слушателя.

## Registry закончил загрузку data/. `error_count` > 0 — данные битые, см. Registry.errors.
signal registry_loaded(error_count: int)

## Игрок приземлился после падения с высоты `fall` блоков (урон от падения — SurvivalController).
signal player_landed(fall: float)

## Мир сохранён (ручное сохранение, автосохранение, выход).
signal world_saved(folder: String)

## Игрок сломал блок (позиция в мире, числовой ID, точка в сцене для звука и частиц).
signal block_broken(pos: Vector3i, block: int, scene_pos: Vector3)

## Игрок поставил блок.
signal block_placed(pos: Vector3i, block: int, scene_pos: Vector3)

## Шаг игрока: группа звуков поверхности (поле `sounds` блока под ногами) и точка в сцене.
signal player_step(sound_group: StringName, scene_pos: Vector3)
