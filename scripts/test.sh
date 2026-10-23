#!/usr/bin/env bash
# Запуск GUT-тестов из tests/. Дополнительные аргументы передаются в GUT,
# например: scripts/test.sh -gselect=test_registry   или   -gunit_test_name=test_air
source "$(dirname "$0")/common.sh"
ensure_godot
cd "$ROOT"
ensure_imported
log "GUT-тесты ..."
mkdir -p build
godot_run --headless --path "$ROOT" -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@"
