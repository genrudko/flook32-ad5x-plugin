#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FLOOK32_PLUGIN_DIR="$HERE"
export FLOOK32_PLUGIN_DIR
. "$HERE/lib/common.sh"

flook32_remove_owned_links
flook32_cleanup_legacy_hook
# DISABLE_PLUGIN removes plugins.cfg itself. Remove only the old pre-lifecycle
# user.cfg include that belonged to our legacy installer.
flook32_remove_exact_line "$FLOOK32_USER_CFG" "$FLOOK32_INCLUDE"

echo 'FLOOK32: disabled; user local config and shared Python packages preserved'
