#!/usr/bin/env bash
# Общие переменные и функции для scripts/*.sh. Подключать через: source "$(dirname "$0")/common.sh"
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2-stable}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_DIR="$ROOT/tools/godot"
GODOT_RELEASES="https://github.com/godotengine/godot/releases/download/$GODOT_VERSION"
# Шаблоны экспорта Godot ищет в ~/.local/share/godot/export_templates/<версия через точку>/
TEMPLATES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION/-/.}"

log() { printf '\033[1;34m[kubach]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[kubach] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

# Скачивает headless-бинарник Godot, если его нет. Путь можно переопределить через $GODOT.
ensure_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		[[ -x "$GODOT" ]] || die "\$GODOT=$GODOT не исполняемый файл"
		return
	fi
	GODOT="$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"
	if [[ ! -x "$GODOT" ]]; then
		log "Скачиваю Godot $GODOT_VERSION в tools/godot/ ..."
		mkdir -p "$GODOT_DIR"
		local zip="$GODOT_DIR/godot.zip"
		curl -sSfL --retry 4 -o "$zip" "$GODOT_RELEASES/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
		unzip -q -o "$zip" -d "$GODOT_DIR"
		rm -f "$zip"
		chmod +x "$GODOT"
	fi
	export GODOT
}

# Ставит шаблоны экспорта для Windows и Linux (только release + debug x86_64, без остального архива).
ensure_templates() {
	local need=(windows_release_x86_64.exe windows_debug_x86_64.exe linux_release.x86_64 linux_debug.x86_64)
	local missing=0
	for f in "${need[@]}"; do [[ -f "$TEMPLATES_DIR/$f" ]] || missing=1; done
	[[ $missing == 0 ]] && return
	local tpz="$GODOT_DIR/cache/Godot_v${GODOT_VERSION}_export_templates.tpz"
	if [[ ! -f "$tpz" ]]; then
		log "Скачиваю шаблоны экспорта (~1.3 ГБ) ..."
		mkdir -p "$(dirname "$tpz")"
		curl -sSfL --retry 4 -o "$tpz.part" "$GODOT_RELEASES/Godot_v${GODOT_VERSION}_export_templates.tpz"
		mv "$tpz.part" "$tpz"
	fi
	mkdir -p "$TEMPLATES_DIR"
	local args=(templates/version.txt)
	for f in "${need[@]}"; do args+=("templates/$f"); done
	unzip -q -o -j "$tpz" "${args[@]}" -d "$TEMPLATES_DIR"
	log "Шаблоны установлены в $TEMPLATES_DIR"
}

# Запуск Godot с таймаутом: при ошибке скрипта в headless-режиме Godot может не выйти сам.
godot_run() {
	timeout --kill-after=10 "${GODOT_TIMEOUT:-600}" "$GODOT" "$@"
}

# Первый импорт проекта: создаёт .godot/ и кэш глобальных классов (class_name).
ensure_imported() {
	# Godot не должен сканировать бинарники и сборки как ресурсы проекта.
	mkdir -p "$ROOT/build" "$GODOT_DIR"
	touch "$ROOT/build/.gdignore" "$GODOT_DIR/.gdignore"
	if [[ ! -f "$ROOT/.godot/global_script_class_cache.cfg" || "${FORCE_IMPORT:-0}" == 1 ]]; then
		log "Импорт проекта ..."
		GODOT_TIMEOUT=300 godot_run --headless --path "$ROOT" --import >/dev/null 2>&1 || true
	fi
}
