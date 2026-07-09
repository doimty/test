# Insulation 0.1.36.40-cli1

## Added

- Added the bundled native CLI tool `insulationctl` with short symlink `ins`.
- Supported commands:
  - `ins` / `ins status`: print the configured CPU mode.
  - `ins off`: set Apple native thermal control.
  - `ins low`: set simulated low-power frequency.
  - `ins max`: set prevent-thermal-downclocking mode.
  - `ins lowPower`: alias for `ins low`.
  - `ins fullPower`: alias for `ins max`.
- Supported flags:
  - `--raw`: print only `off`, `low`, or `max`.
  - `--quiet`: suppress success output.
  - `help`, `--help`, `-h`: print usage.

## Behavior

- `status` is read-only and has no owner repair, notification, or restart side effects.
- Mode changes write `thermalPowerMode`, post the runtime/apply notifications, and trigger the normal `thermalmonitord` restart path.
- The tool is not setuid. It supports normal `root` and `mobile` execution. Root mode changes repair the prefs file owner to `mobile:mobile` after writing.
- Install/upgrade does not create a prefs file. `postinst` only repairs owner on existing prefs files and keeps the existing `thermalmonitord` restart behavior.
- Invalid stored prefs values fall back to `off`, matching tweak runtime behavior.

## Exit codes

- `0`: success
- `64`: argument or usage error
- `74`: prefs read/write failure
- `75`: notification/restart trigger failure after prefs were saved

## Scope

This release only adds the CLI control surface and packaging smoke checks. It does not change thermal strategy, hooks, boot guard, probe timing, or low/max CPU behavior.
