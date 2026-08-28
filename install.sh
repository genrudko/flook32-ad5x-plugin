#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FLOOK32_PLUGIN_DIR="$HERE"
export FLOOK32_PLUGIN_DIR
. "$HERE/lib/common.sh"

rollback_include() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$rc" -ne 0 ]; then
        # Z-Mod adds the include before invoking install.sh. If setup fails,
        # remove only our exact include so the following FIRMWARE_RESTART does
        # not leave Klipper unable to boot.
        flook32_remove_exact_line "$FLOOK32_PLUGINS_CFG" "$FLOOK32_INCLUDE" || true
        echo 'ERROR: FLOOK32 installation failed; plugin include rolled back.' >&2
    fi
    exit "$rc"
}
trap rollback_include EXIT HUP INT TERM

flook32_prepare
trap - EXIT HUP INT TERM
echo 'FLOOK32: installed via Z-Mod plugin lifecycle'
