# Changelog

## 0.2.0

- Repackage the hardware-proven AD5X FLOOK32 integration as a native Z-Mod plugin.
- Add `install.sh`, `update.sh`, `uninstall.sh`, and `status.sh` lifecycle hooks.
- Support both Z-Mod 1.7.2 and the relocated 1.7.3+ Klipper repository.
- Prefer the actually running `klippy.py` path before known fallback locations.
- Remove the legacy `power_on.sh` / `ensure.sh` self-heal mechanism during migration.
- Keep local config overrides in Git-ignored `flook32.local*.cfg` files.
- Add fail-closed ownership checks for the Klipper `flook32.py` seam.
- Preserve `websocket-client==1.8.0` with HTTP fallback.
- Preserve native Chamber, Chamber Heater, and OrcaSlicer M141/M191 behavior from v0.1.0.
