#!/usr/bin/env bash
# Экспорт релизной сборки под Linux: build/linux/Kubach.x86_64.
source "$(dirname "$0")/common.sh"
ensure_godot
ensure_templates
cd "$ROOT"
ensure_imported
mkdir -p build/linux
log "Экспорт Linux ..."
godot_run --headless --path "$ROOT" --export-release "Linux" "$ROOT/build/linux/Kubach.x86_64"
[[ -s build/linux/Kubach.x86_64 ]] || die "Kubach.x86_64 не создан"
ls -lh build/linux/
