# FLOOK32 plugin for Flashforge AD5X / Z-Mod

Native Z-Mod plugin packaging for [`schreider/flook32`](https://github.com/schreider/flook32), adapted and hardware-tested on Flashforge AD5X.

The ESP32 remains the physical heater/PID/safety authority. Klipper exposes the chamber as a normal `heater_generic chamber`, plus read-only heater-body telemetry.

## Features

- stock Fluidd/Mainsail `Chamber` target and power control;
- separate read-only `Chamber Heater` sensor;
- standard `SET_HEATER_TEMPERATURE HEATER=chamber TARGET=...`;
- OrcaSlicer `M141` / `M191` integration;
- FLOOK32 WebSocket transport with HTTP fallback;
- Z-Mod `ENABLE_PLUGIN` / `DISABLE_PLUGIN` lifecycle;
- `install.sh`, `update.sh`, and `uninstall.sh` hooks;
- automatic AD5X Klipper path detection for the 1.7.2 and 1.7.3+ layouts;
- migration cleanup for the earlier manual `power_on.sh`/`ensure.sh` installation.

## Compatibility

Validated integration code originates from hardware-tested AD5X commit `10ceeeb88558198cd62b4677f81eb4dad7fe8ffd` in `genrudko/Plugins_AD5X`.

Known Z-Mod layouts handled by the lifecycle scripts:

- Z-Mod 1.7.2: `/usr/data/config/base/klipper`
- Z-Mod 1.7.3+: `/usr/data/zmod/klipper`
- fallback stock/wiki layout: `/usr/prog/klipper`

Klipper Python on AD5X is expected at `/usr/prog/Python-3.8.2/bin/python3`.

## Register with Z-Mod

Add to `mod_data/user.moonraker.conf`:

```ini
[update_manager flook32]
type: git_repo
channel: dev
path: /root/printer_data/config/mod_data/plugins/flook32
origin: https://github.com/genrudko/flook32-ad5x-plugin.git
is_system_service: False
primary_branch: main
```

Then enable from the Klipper console:

```gcode
ENABLE_PLUGIN name=flook32
```

Disable cleanly with:

```gcode
DISABLE_PLUGIN name=flook32
```

Z-Mod owns the `plugins.cfg` include and invokes this repository's lifecycle scripts. No FLOOK-specific boot hook is required.

## Legacy migration

The older AD5X integration stored non-Git files directly in `/opt/config/mod_data/plugins/flook32` and repaired a Klipper symlink from `power_on.sh`. That directory must be adopted once before `ENABLE_PLUGIN` can manage it as a Git repository.

Before adoption, preserve the existing config as `/opt/config/mod_data/flook32-legacy.cfg`. On first lifecycle install it is imported as ignored `flook32.local.cfg`, so local overrides survive future Git updates without making the plugin repository dirty.

Do not delete the old installation until that config has been stashed.

## Local overrides

Tracked defaults live in `flook32.cfg`. Optional `flook32.local*.cfg` files are Git-ignored and loaded afterwards, so they can override the same sections without blocking Moonraker updates.

## Credits and license

Upstream FLOOK32 source pin: `477d756c1d73720015299cad66012fce7f5f502a`.

The FLOOK32 Python module is derived from `schreider/flook32` and is distributed under GNU GPL v3; see `LICENSE`.

### Transactional migration helper

For an existing pre-lifecycle installation, `migrate_legacy.sh` performs the one-time adoption transaction:

1. snapshots `user.cfg`, `power_on.sh`, and `user.moonraker.conf`;
2. preserves the old `flook32.cfg` as `mod_data/flook32-legacy.cfg`;
3. parks the whole old plugin directory as a timestamped backup;
4. registers `[update_manager flook32]`;
5. calls Z-Mod's own `plugins.sh ... Enable` path;
6. rolls the old installation back if clone/install verification fails.

After successful adoption, all normal enable/disable/update operations are handled by Z-Mod itself.
