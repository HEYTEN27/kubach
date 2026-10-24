#!/usr/bin/env bash
# Сборка нативного расширения (native/kubach_native) под Linux и Windows x86_64.
#   scripts/build_native.sh            — обе платформы
#   scripts/build_native.sh linux      — только Linux
# Нужны: g++, python3 с пакетами scons и ziglang (pip install scons ziglang).
# Windows собирается кросс-компиляцией: zig выступает в роли MinGW-clang.
# Готовые библиотеки кладутся в native/bin/ и коммитятся — на ПК собирать ничего не нужно.
source "$(dirname "$0")/common.sh"
cd "$ROOT"
GODOT_CPP_TAG="${GODOT_CPP_TAG:-godot-4.5-stable}"
if [[ ! -f tools/godot-cpp/SConstruct ]]; then
	log "Скачиваю godot-cpp ($GODOT_CPP_TAG) ..."
	git clone -q --depth 1 --branch "$GODOT_CPP_TAG" https://github.com/godotengine/godot-cpp.git tools/godot-cpp
fi
JOBS="$(nproc)"
platforms=("${@:-linux windows}")
for p in ${platforms[@]}; do
	case "$p" in
		linux)
			log "Сборка Linux x86_64 ..."
			(cd native/kubach_native && scons -j"$JOBS" platform=linux arch=x86_64 target=template_release)
			;;
		windows)
			log "Сборка Windows x86_64 (zig) ..."
			ZB="$ROOT/tools/zig-mingw/bin"
			mkdir -p "$ZB"
			# Обёртки под имена MinGW-clang. У zig своя libc++ (линкуется статически): флаги
			# статической libstdc++ убираем, -lstdc++ заменяем на -lc++.
			for tool in clang clang++; do
				cat > "$ZB/x86_64-w64-mingw32-$tool" <<WRAP
#!/usr/bin/env bash
args=()
for a in "\$@"; do
	case "\$a" in -static|-static-libgcc|-static-libstdc++) ;; -lstdc++) args+=("-lc++") ;; *) args+=("\$a") ;; esac
done
export ZIG_GLOBAL_CACHE_DIR="$ZB/../cache" ZIG_LOCAL_CACHE_DIR="$ZB/../cache"
exec python3 -m ziglang $([[ $tool == clang ]] && echo cc || echo c++) -target x86_64-windows-gnu "\${args[@]}"
WRAP
			done
			for t in ar ranlib; do
				name="x86_64-w64-mingw32-$t"
				[[ $t == ar ]] && name="x86_64-w64-mingw32-llvm-ar"
				printf '#!/usr/bin/env bash\nexport ZIG_GLOBAL_CACHE_DIR="%s/../cache" ZIG_LOCAL_CACHE_DIR="%s/../cache"\nexec python3 -m ziglang %s "$@"\n' "$ZB" "$ZB" "$t" > "$ZB/$name"
			done
			chmod +x "$ZB"/*
			(cd native/kubach_native && PATH="$ZB:$PATH" scons -j"$JOBS" platform=windows arch=x86_64 target=template_release \
				use_mingw=yes use_llvm=yes)
			;;
		*) die "неизвестная платформа: $p" ;;
	esac
done
ls -lh native/bin/
