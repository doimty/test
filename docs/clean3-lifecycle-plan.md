# Insulation 0.1.37 clean3 lifecycle plan

Baseline: `446e813b74fe426963e84ccb8efab8f2659f90de`

## Hypothesis

Persistent `OSThermalStatus.plist` overrides survive because cleanup depends on
process-local transition memory and package removal has no native-state cleanup.
Mode-change notifications can also terminate `thermalmonitord` before an apply
has completed.

## Success criteria

- Off and low-power applies remove `engageBehavior*` based on actual
  `SCPreferences` state, including on a fresh process.
- Independent thermal options remain independent of CPU mode: enabled options
  keep their override; disabled options remove their own plugin-written keys.
- Package removal clears the full nine-key owner set regardless of prefs.
- Package removal invokes one idempotent native-state cleanup entrypoint before
  restarting `thermalmonitord`.
- A CPU mode change produces one daemon apply, and restart happens only after
  that serialized apply returns.
- Rootless and roothide packages still build without arm64e ABI warnings.

## Independent failure signals

- Any path still gates native cleanup only on `static` Last/Owned variables.
- `runtimeState` and `executePuppetEvent` both invoke the same apply callback.
- A producer posts a restart notification immediately after an apply
  notification.
- The package has no executable pre-removal cleanup path.
- Host tests, source contracts, either package build, ABI scan, or package
  payload inspection fails.

## Ablation expectations

- With no SC keys present, cleanup performs no commit and succeeds.
- With only one plugin-owned key present, cleanup removes that key without
  creating native-default replacement keys.
- Repeating cleanup is a no-op success.
- Removing the tweak while prefs still request fullPower clears all nine keys
  written by Insulation before the daemon restarts.

## Evidence plan

1. Host parser and source-contract tests.
2. Rootless compile/package smoke check.
3. Roothide cloud build for deliverable ABI validation.
4. Extract package maintainer scripts and Mach-O payload for inspection.
5. Scan source, binaries, and build logs for forbidden legacy notification and
   ABI-warning strings.
