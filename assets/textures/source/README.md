# Исходные CC0 PBR-текстуры

Сюда кладутся оригиналы (ambientCG, Poly Haven и т.п., только CC0) в полном разрешении: albedo/color, normal (OpenGL), roughness, AO, height.
Раскладка: `assets/textures/source/<набор>/<набор>_<карта>.png`, например `granite/granite_color.png`.
Пайплайн этапа 3 режет, уменьшает до 64/128/256 и упаковывает в Texture2DArray (`assets/textures/generated/`).
Если для набора нет исходника, его генерирует `tools/texgen/`.
