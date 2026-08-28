#!/bin/sh
set -u
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FLOOK32_PLUGIN_DIR="$HERE"
export FLOOK32_PLUGIN_DIR
. "$HERE/lib/common.sh"

echo '=== FLOOK32 AD5X plugin status ==='
echo "PLUGIN: $FLOOK32_PLUGIN_DIR"
if root="$(flook32_detect_klipper_root 2>/dev/null)"; then
    echo "KLIPPER: $root"
    dest="$root/klippy/extras/flook32.py"
    if [ -L "$dest" ]; then echo "LINK: $dest -> $(readlink "$dest")"; else echo 'LINK: missing'; fi
else
    echo 'KLIPPER: not detected'
fi
if grep -qxF "$FLOOK32_INCLUDE" "$FLOOK32_PLUGINS_CFG" 2>/dev/null; then echo 'PLUGIN INCLUDE: enabled'; else echo 'PLUGIN INCLUDE: disabled'; fi
if grep -qxF "$FLOOK32_INCLUDE" "$FLOOK32_USER_CFG" 2>/dev/null; then echo 'LEGACY user.cfg INCLUDE: present'; else echo 'LEGACY user.cfg INCLUDE: clean'; fi
if grep -Fq '# >>> FLOOK32_BOOT_ENSURE >>>' "$FLOOK32_POWER_ON" 2>/dev/null; then echo 'LEGACY power_on hook: present'; else echo 'LEGACY power_on hook: clean'; fi
flook32_export_python_env
if "$FLOOK32_PYTHON" - <<'PY' >/dev/null 2>&1
import websocket
assert websocket.__version__ == '1.8.0'
PY
then echo 'WEBSOCKET: 1.8.0'; else echo 'WEBSOCKET: unavailable (HTTP fallback)'; fi
