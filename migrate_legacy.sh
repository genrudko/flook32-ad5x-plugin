#!/bin/sh
# One-time transactional adoption of the pre-Z-Mod-lifecycle AD5X install.
set -eu

MOD_DATA="${FLOOK32_MOD_DATA:-/opt/config/mod_data}"
OLD_DIR="${FLOOK32_OLD_DIR:-$MOD_DATA/plugins/flook32}"
USER_CFG="${FLOOK32_USER_CFG:-$MOD_DATA/user.cfg}"
POWER_ON="${FLOOK32_POWER_ON:-$MOD_DATA/power_on.sh}"
MOON_CFG="${FLOOK32_MOON_CFG:-$MOD_DATA/user.moonraker.conf}"
PLUGINS_CFG="${FLOOK32_PLUGINS_CFG:-$MOD_DATA/plugins.cfg}"
STASH="${FLOOK32_LEGACY_STASH:-$MOD_DATA/flook32-legacy.cfg}"
ORIGIN="${FLOOK32_ORIGIN:-https://github.com/genrudko/flook32-ad5x-plugin.git}"
INCLUDE='[include plugins/flook32/flook32.cfg]'
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${FLOOK32_BACKUP_DIR:-$MOD_DATA/flook32-legacy-backup-$STAMP}"
SNAP="${FLOOK32_MIGRATION_SNAPSHOT:-$MOD_DATA/.flook32-migration-$STAMP}"
SUCCESS=0
MOVED_LEGACY=0
ALREADY_ADOPTED=0

mkdir -p "$SNAP"
for item in "$USER_CFG" "$POWER_ON" "$MOON_CFG" "$PLUGINS_CFG"; do
    key="$(basename "$item")"
    if [ -e "$item" ]; then cp -p "$item" "$SNAP/$key"; else : > "$SNAP/.absent-$key"; fi
done

restore_file() {
    file="$1"; key="$(basename "$file")"
    rm -f "$file"
    [ -f "$SNAP/$key" ] && cp -p "$SNAP/$key" "$file"
}

rollback() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$SUCCESS" -ne 1 ]; then
        echo 'ERROR: migration failed; restoring legacy FLOOK32 state' >&2
        if [ "$MOVED_LEGACY" -eq 1 ]; then
            rm -rf "$OLD_DIR"
            [ -d "$BACKUP" ] && mv "$BACKUP" "$OLD_DIR"
        fi
        restore_file "$USER_CFG"
        restore_file "$POWER_ON"
        restore_file "$MOON_CFG"
        restore_file "$PLUGINS_CFG"
    fi
    exit "$rc"
}
trap rollback EXIT HUP INT TERM

[ -d "$OLD_DIR" ] || { echo "ERROR: legacy directory not found: $OLD_DIR" >&2; exit 1; }
if [ -d "$OLD_DIR/.git" ]; then
    current="$(git -C "$OLD_DIR" config --get remote.origin.url 2>/dev/null || true)"
    if [ "$current" = "$ORIGIN" ]; then
        ALREADY_ADOPTED=1
        echo 'FLOOK32 standalone repository already present; repairing lifecycle state.'
    else
        echo "ERROR: $OLD_DIR is already a different Git repository" >&2
        exit 1
    fi
fi

if [ "$ALREADY_ADOPTED" -eq 0 ]; then
    [ -f "$OLD_DIR/flook32.cfg" ] || { echo 'ERROR: legacy flook32.cfg is missing' >&2; exit 1; }
    cp -p "$OLD_DIR/flook32.cfg" "$STASH"
    [ ! -e "$BACKUP" ] || { echo "ERROR: backup already exists: $BACKUP" >&2; exit 1; }
    mv "$OLD_DIR" "$BACKUP"
    MOVED_LEGACY=1
fi

# Remove the pre-lifecycle config include while the old directory is parked.
if [ -f "$USER_CFG" ]; then
    grep -Fvx "$INCLUDE" "$USER_CFG" > "$USER_CFG.tmp" || true
    mv "$USER_CFG.tmp" "$USER_CFG"
fi

# Remove only our old boot self-heal marker block.
if [ -f "$POWER_ON" ]; then
    bc="$(grep -Fxc '# >>> FLOOK32_BOOT_ENSURE >>>' "$POWER_ON" 2>/dev/null || true)"
    ec="$(grep -Fxc '# <<< FLOOK32_BOOT_ENSURE <<<' "$POWER_ON" 2>/dev/null || true)"
    [ "$bc" = "$ec" ] || { echo 'ERROR: malformed legacy power_on marker block' >&2; exit 1; }
    [ "$bc" -le 1 ] || { echo 'ERROR: duplicate legacy power_on marker blocks' >&2; exit 1; }
    if [ "$bc" -eq 1 ]; then
        awk '
          /# >>> FLOOK32_BOOT_ENSURE >>>/ {skip=1; next}
          /# <<< FLOOK32_BOOT_ENSURE <<</ {skip=0; next}
          !skip {print}
        ' "$POWER_ON" > "$POWER_ON.tmp"
        mv "$POWER_ON.tmp" "$POWER_ON"
        chmod 0755 "$POWER_ON" 2>/dev/null || true
    fi
fi

[ -f "$MOON_CFG" ] || : > "$MOON_CFG"
if grep -q '^\[update_manager flook32\]$' "$MOON_CFG" 2>/dev/null; then
    section="$(awk '
      /^\[update_manager flook32\]$/ {on=1; next}
      /^\[/ && on {exit}
      on {print}
    ' "$MOON_CFG")"
    printf '%s\n' "$section" | grep -Fq "origin: $ORIGIN" || {
        echo 'ERROR: an existing [update_manager flook32] points somewhere else' >&2
        exit 1
    }
else
    cat >> "$MOON_CFG" <<EOF2

[update_manager flook32]
type: git_repo
channel: dev
path: /root/printer_data/config/mod_data/plugins/flook32
origin: $ORIGIN
is_system_service: False
primary_branch: main
EOF2
fi

if [ -n "${FLOOK32_PLUGIN_DRIVER:-}" ]; then
    DRIVER="$FLOOK32_PLUGIN_DRIVER"
elif [ -x /usr/data/zmod/zmod/.shell/plugins.sh ]; then
    DRIVER=/usr/data/zmod/zmod/.shell/plugins.sh
elif [ -x /opt/config/mod/.shell/plugins.sh ]; then
    DRIVER=/opt/config/mod/.shell/plugins.sh
elif [ -x /usr/data/config/mod/.shell/plugins.sh ]; then
    DRIVER=/usr/data/config/mod/.shell/plugins.sh
else
    echo 'ERROR: Z-Mod plugins.sh not found' >&2
    exit 1
fi

"$DRIVER" flook32 Enable
[ -d "$OLD_DIR/.git" ] || { echo 'ERROR: Z-Mod did not clone the standalone plugin' >&2; exit 1; }
[ -f "$OLD_DIR/flook32.py" ] || { echo 'ERROR: standalone flook32.py missing after enable' >&2; exit 1; }
if ! grep -qxF "$INCLUDE" "$PLUGINS_CFG" 2>/dev/null; then
    echo 'ERROR: Z-Mod returned success but FLOOK32 include is not enabled (install hook likely failed)' >&2
    exit 1
fi

SUCCESS=1
trap - EXIT HUP INT TERM
rm -rf "$SNAP"
echo "FLOOK32 migration complete. Legacy backup preserved at: $BACKUP"
echo "Legacy config stash: $STASH"
