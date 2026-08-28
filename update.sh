#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
FLOOK32_PLUGIN_DIR="$HERE"
export FLOOK32_PLUGIN_DIR
. "$HERE/lib/common.sh"
flook32_prepare
echo 'FLOOK32: update hook completed; Klipper restart may be required for Python changes'
