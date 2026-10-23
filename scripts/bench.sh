#!/usr/bin/env bash
# CPU-бенчмарки (без видеокарты): генерация, мешинг, вода, свет и т.п. — то, что не зависит от GPU.
# Результат: build/bench/cpu_bench.json; сравнение с tools/bench/baseline.json.
#   scripts/bench.sh            — прогнать и сравнить
#   scripts/bench.sh --strict   — упасть, если что-то стало медленнее порога
#   scripts/bench.sh --update-baseline — записать текущие цифры как эталон
source "$(dirname "$0")/common.sh"
ensure_godot
cd "$ROOT"
ensure_imported
mkdir -p build/bench
godot_run --headless --path "$ROOT" res://tools/bench/cpu_bench.tscn -- "$@"
