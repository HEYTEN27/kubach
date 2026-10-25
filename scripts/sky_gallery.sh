#!/usr/bin/env bash
# Визуальная проверка неба: сетка «время × погода», кадр в PNG (программный OpenGL под Xvfb).
#   scripts/sky_gallery.sh [out.png]
source "$(dirname "$0")/common.sh"
ensure_godot
cd "$ROOT"
FORCE_IMPORT=1 ensure_imported
out="${1:-$ROOT/build/sky_gallery.png}"
shift || true
timeout --kill-after=10 300 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$ROOT" --audio-driver Dummy \
	--resolution 1280x720 res://tools/render_test/sky_gallery.tscn -- --out="$out" "$@" 2>&1 \
	| grep -P 'Галерея|Небо|SCRIPT ERROR|SHADER|ERROR: (?!Required Vulkan|Condition "err != OK")' || true
[[ -s "$out" ]] || die "кадр не создан"
