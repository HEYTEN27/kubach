#!/usr/bin/env bash
# Визуальная проверка шейдеров блоков: ряд блоков, кадр в PNG (программный OpenGL под Xvfb).
#   scripts/gallery.sh [out.png] [--blocks=granite,turf,...]
source "$(dirname "$0")/common.sh"
ensure_godot
cd "$ROOT"
FORCE_IMPORT=1 ensure_imported
out="${1:-$ROOT/build/gallery.png}"
shift || true
timeout --kill-after=10 300 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$ROOT" --audio-driver Dummy \
	--resolution 1280x720 res://tools/render_test/block_gallery.tscn -- --out="$out" "$@" 2>&1 \
	| grep -P 'Галерея|SCRIPT ERROR|SHADER|ERROR: (?!Required Vulkan|Condition "err != OK")' || true
[[ -s "$out" ]] || die "кадр не создан"
