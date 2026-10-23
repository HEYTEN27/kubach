#!/usr/bin/env bash
# Проверка проекта без запуска игры:
#   1) все data/**/*.json — валидный JSON;
#   2) все наши .gd компилируются (с автозагрузками, addons/ пропускаются);
#   3) Registry загружает data/ без ошибок.
source "$(dirname "$0")/common.sh"
ensure_godot
cd "$ROOT"
FORCE_IMPORT=1 ensure_imported

fail=0

log "JSON в data/ ..."
while IFS= read -r -d '' f; do
	python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" 2>/dev/null \
		|| { echo "  ✗ $f: невалидный JSON"; fail=1; }
done < <(find data -name '*.json' -print0)

log "Компиляция GDScript и загрузка data/ ..."
out=$(godot_run --headless --path "$ROOT" res://tools/check/check_project.tscn 2>&1) || fail=1
# Сообщения компилятора (SCRIPT ERROR / Parse Error) + итог проверки.
echo "$out" | grep -E '^(OK|✗|  )|SCRIPT ERROR|Parse Error|ERROR:' | grep -vE '^ +(at:|GDScript backtrace|\[[0-9]+\])' || true

if [[ $fail != 0 ]]; then die "check.sh: есть ошибки"; fi
log "check.sh: всё чисто"
