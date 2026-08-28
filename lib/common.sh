#!/bin/sh
# Shared lifecycle helpers for the AD5X/Z-Mod FLOOK32 plugin.

FLOOK32_PLUGIN_DIR="${FLOOK32_PLUGIN_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
FLOOK32_MOD_DATA="${FLOOK32_MOD_DATA:-/opt/config/mod_data}"
FLOOK32_POWER_ON="${FLOOK32_POWER_ON:-$FLOOK32_MOD_DATA/power_on.sh}"
FLOOK32_USER_CFG="${FLOOK32_USER_CFG:-$FLOOK32_MOD_DATA/user.cfg}"
FLOOK32_PLUGINS_CFG="${FLOOK32_PLUGINS_CFG:-$FLOOK32_MOD_DATA/plugins.cfg}"
FLOOK32_PYTHON="${FLOOK32_PYTHON:-/usr/prog/Python-3.8.2/bin/python3}"
FLOOK32_INCLUDE='[include plugins/flook32/flook32.cfg]'
FLOOK32_SRC="$FLOOK32_PLUGIN_DIR/flook32.py"
FLOOK32_LOCAL_CFG="$FLOOK32_PLUGIN_DIR/flook32.local.cfg"
FLOOK32_LEGACY_STASH="${FLOOK32_LEGACY_STASH:-$FLOOK32_MOD_DATA/flook32-legacy.cfg}"

flook32_export_python_env() {
    export LD_LIBRARY_PATH="/usr/prog/Python-3.8.2/lib:/usr/prog/openssl-1.0.2d/lib:/usr/prog/libffi-3.4.4/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
}

flook32_detect_klipper_root() {
    if [ -n "${FLOOK32_KLIPPER_ROOT:-}" ]; then
        [ -d "$FLOOK32_KLIPPER_ROOT/klippy/extras" ] || return 1
        printf '%s\n' "$FLOOK32_KLIPPER_ROOT"
        return 0
    fi
    # Prefer the currently running Klipper process. This survives future
    # Z-Mod directory migrations without waiting for a plugin release.
    for cmdline in /proc/[0-9]*/cmdline; do
        [ -r "$cmdline" ] || continue
        runtime="$(tr '\000' '\n' < "$cmdline" 2>/dev/null | sed -n '\|/klippy/klippy.py$|p' | head -n 1)"
        [ -n "$runtime" ] || continue
        root="${runtime%/klippy/klippy.py}"
        if [ -f "$root/klippy/klippy.py" ] && [ -d "$root/klippy/extras" ]; then
            printf '%s\n' "$root"
            return 0
        fi
    done
    # Known AD5X layouts, newest first.
    for root in \
        /usr/data/zmod/klipper \
        /usr/data/config/base/klipper \
        /opt/config/base/klipper \
        /usr/prog/klipper
    do
        if [ -f "$root/klippy/klippy.py" ] && [ -d "$root/klippy/extras" ]; then
            printf '%s\n' "$root"
            return 0
        fi
    done
    return 1
}

flook32_known_klipper_roots() {
    [ -n "${FLOOK32_KLIPPER_ROOT:-}" ] && printf '%s\n' "$FLOOK32_KLIPPER_ROOT"
    printf '%s\n' \
        /usr/data/zmod/klipper \
        /usr/data/config/base/klipper \
        /opt/config/base/klipper \
        /usr/prog/klipper
}

flook32_validate_python() {
    [ -x "$FLOOK32_PYTHON" ] || {
        echo "ERROR: Klipper Python not found: $FLOOK32_PYTHON" >&2
        return 1
    }
    flook32_export_python_env
    "$FLOOK32_PYTHON" - "$FLOOK32_SRC" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
}

flook32_add_git_exclude() {
    root="$1"
    exclude="$root/.git/info/exclude"
    if [ -d "$root/.git/info" ]; then
        grep -qxF '/klippy/extras/flook32.py' "$exclude" 2>/dev/null || \
            printf '%s\n' '/klippy/extras/flook32.py' >> "$exclude"
    fi
}

flook32_remove_git_exclude() {
    root="$1"
    exclude="$root/.git/info/exclude"
    [ -f "$exclude" ] || return 0
    grep -Fvx '/klippy/extras/flook32.py' "$exclude" > "$exclude.tmp" || true
    mv "$exclude.tmp" "$exclude"
}

flook32_link_runtime() {
    root="$(flook32_detect_klipper_root)" || {
        echo 'ERROR: active Klipper repository not found' >&2
        return 1
    }
    dest="$root/klippy/extras/flook32.py"
    src_real="$(readlink -f "$FLOOK32_SRC")"
    if [ -L "$dest" ]; then
        if [ "$(readlink -f "$dest" 2>/dev/null || true)" != "$src_real" ]; then
            echo "ERROR: foreign symlink already owns $dest -> $(readlink "$dest" 2>/dev/null || true)" >&2
            return 1
        fi
    elif [ -e "$dest" ]; then
        echo "ERROR: refusing to replace non-symlink Klipper module: $dest" >&2
        return 1
    else
        ln -s "$FLOOK32_SRC" "$dest"
    fi
    flook32_add_git_exclude "$root"
    printf '%s\n' "$root"
}

flook32_remove_owned_links() {
    src_real="$(readlink -f "$FLOOK32_SRC" 2>/dev/null || printf '%s' "$FLOOK32_SRC")"
    seen=''
    flook32_known_klipper_roots | while IFS= read -r root; do
        [ -n "$root" ] || continue
        case " $seen " in *" $root "*) continue ;; esac
        seen="$seen $root"
        dest="$root/klippy/extras/flook32.py"
        if [ -L "$dest" ] && [ "$(readlink -f "$dest" 2>/dev/null || true)" = "$src_real" ]; then
            rm -f "$dest"
            flook32_remove_git_exclude "$root"
        elif [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            # A stale exclude with no module at all can only hide our old seam.
            flook32_remove_git_exclude "$root"
        fi
    done
}

flook32_remove_marker_block() {
    file="$1"; begin="$2"; end="$3"
    [ -f "$file" ] || return 0
    bc="$(grep -Fxc "$begin" "$file" 2>/dev/null || true)"
    ec="$(grep -Fxc "$end" "$file" 2>/dev/null || true)"
    [ "$bc" = "$ec" ] || {
        echo "ERROR: malformed marker block in $file" >&2
        return 1
    }
    [ "$bc" -le 1 ] || {
        echo "ERROR: duplicate marker blocks in $file" >&2
        return 1
    }
    [ "$bc" -eq 1 ] || return 0
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skip=1; next }
      $0 == end   { skip=0; next }
      !skip { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
}

flook32_cleanup_legacy_hook() {
    flook32_remove_marker_block "$FLOOK32_POWER_ON" \
        '# >>> FLOOK32_BOOT_ENSURE >>>' '# <<< FLOOK32_BOOT_ENSURE <<<'
    [ -f "$FLOOK32_POWER_ON" ] && chmod 0755 "$FLOOK32_POWER_ON" 2>/dev/null || true
}

flook32_remove_exact_line() {
    file="$1"; line="$2"
    [ -f "$file" ] || return 0
    grep -Fvx "$line" "$file" > "$file.tmp" || true
    mv "$file.tmp" "$file"
}

flook32_cleanup_legacy_include_if_managed() {
    if [ -f "$FLOOK32_PLUGINS_CFG" ] && \
       grep -qxF "$FLOOK32_INCLUDE" "$FLOOK32_PLUGINS_CFG" 2>/dev/null; then
        flook32_remove_exact_line "$FLOOK32_USER_CFG" "$FLOOK32_INCLUDE"
    fi
}

flook32_import_legacy_config() {
    [ -f "$FLOOK32_LOCAL_CFG" ] && return 0
    [ -f "$FLOOK32_LEGACY_STASH" ] || return 0
    cp -p "$FLOOK32_LEGACY_STASH" "$FLOOK32_LOCAL_CFG"
    chmod 0644 "$FLOOK32_LOCAL_CFG"
    # Older upstream installs exposed [temperature_sensor chamber]. Normalize
    # that legacy FLOOK32 section before it is layered over tracked defaults.
    migrator="$FLOOK32_PLUGIN_DIR/tools/migrate_cfg.py"
    if [ -f "$migrator" ]; then
        flook32_export_python_env
        result="$("$FLOOK32_PYTHON" "$migrator" "$FLOOK32_LOCAL_CFG")" || return 1
        echo "CONFIG MIGRATION: $result"
    fi
    echo "CONFIG: imported legacy settings into $(basename "$FLOOK32_LOCAL_CFG")"
}

flook32_ensure_websocket() {
    flook32_export_python_env
    if "$FLOOK32_PYTHON" - <<'PY' >/dev/null 2>&1
import websocket
assert websocket.__version__ == '1.8.0'
PY
    then
        echo 'WEBSOCKET: 1.8.0 OK'
        return 0
    fi
    if [ "${FLOOK32_SKIP_PIP:-0}" = 1 ]; then
        echo 'WEBSOCKET: missing (test/skip mode); HTTP fallback remains available'
        return 0
    fi
    echo 'WEBSOCKET: installing websocket-client 1.8.0'
    if "$FLOOK32_PYTHON" -m pip install --no-cache-dir --disable-pip-version-check 'websocket-client==1.8.0'; then
        echo 'WEBSOCKET: installed'
    else
        echo 'WARNING: websocket install failed; HTTP fallback remains available' >&2
    fi
}

flook32_prepare() {
    [ -f "$FLOOK32_SRC" ] || { echo "ERROR: missing $FLOOK32_SRC" >&2; return 1; }
    flook32_validate_python || return 1
    flook32_import_legacy_config || return 1
    root="$(flook32_link_runtime)" || return 1
    flook32_cleanup_legacy_hook || return 1
    flook32_cleanup_legacy_include_if_managed || return 1
    flook32_ensure_websocket || return 1
    rm -f "$FLOOK32_PLUGIN_DIR/ensure.sh" 2>/dev/null || true
    echo "KLIPPER: $root"
}
