#!/usr/bin/env bash
# Визуальный смоук-тест в облаке: запускает игру под Xvfb с программным рендером и сохраняет кадр.
#   scripts/screenshot.sh [файл.png] [доп. аргументы игры после --]
# ВАЖНО: без видеокарты Vulkan недоступен, Godot падает на OpenGL 3 (Compatibility).
# Картинка подтверждает, что сцена собирается и UI рисуется, но не показывает
# Forward+-эффекты (SSAO, SSIL, объёмный туман) и ничего не говорит о FPS.
source "$(dirname "$0")/common.sh"
ensure_godot
cd "$ROOT"
FORCE_IMPORT=1 ensure_imported
out="${1:-$ROOT/build/screenshot.png}"
shift || true
command -v xvfb-run >/dev/null || die "нужен xvfb-run (apt install xvfb)"
# Разрешение кадра: llvmpipe рисует шейдеры блоков (массивы текстур, анизотропия) медленно,
# поэтому по умолчанию 1280×720. SHOT_SIZE=1920x1080 SHOT_TIMEOUT=400 — крупнее и дольше.
SIZE="${SHOT_SIZE:-1280x720}"
godot_run_xvfb() { timeout --kill-after=10 "${SHOT_TIMEOUT:-300}" xvfb-run -a -s "-screen 0 ${SIZE}x24" "$GODOT" "$@"; }
godot_run_xvfb --path "$ROOT" --audio-driver Dummy --resolution "$SIZE" -- --screenshot="$out" "$@" 2>&1 | grep -P 'Скриншот|SCRIPT ERROR|ERROR: (?!Required Vulkan|Condition "err != OK")' || true
[[ -s "$out" ]] || die "скриншот не создан"
