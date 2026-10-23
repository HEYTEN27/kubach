#!/usr/bin/env bash
# Экспорт релизной сборки под Windows: build/windows/Kubach.exe (pck встроен в exe).
source "$(dirname "$0")/common.sh"
ensure_godot
ensure_templates
cd "$ROOT"
ensure_imported
mkdir -p build/windows
log "Экспорт Windows ..."
godot_run --headless --path "$ROOT" --export-release "Windows Desktop" "$ROOT/build/windows/Kubach.exe"
[[ -s build/windows/Kubach.exe ]] || die "Kubach.exe не создан"
ls -lh build/windows/
