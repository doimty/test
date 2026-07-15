# Progress

## 2026-07-15 clean3 lifecycle

- Baseline locked at `446e813b74fe426963e84ccb8efab8f2659f90de`.
- Branch created: `fix/insulation-0.1.37-clean3-lifecycle`.
- Residual review accepted: P0 native-state lifecycle first; notification and
  state-machine work follow after cleanup evidence closes.
- Plan: `docs/clean3-lifecycle-plan.md`.
- P0 red tests added for hidden reset action, nine-key cleanup, off/low cleanup,
  independent-option cleanup, and package pre-removal cleanup.
- Shared `InsulationNativeState` now deletes actual SCPreferences keys
  idempotently; CLI hidden reset and `prerm` are wired.
- Parser tests, native-state contract tests, ObjC source checks, shell syntax,
  and `git diff --check` pass.
- First rootless package build passed; package contains executable `prerm` and
  `insulationctl`. Local arm64e warnings make it compile evidence only.
- Mode notification red test added, then legacy `runtimeState` and independent
  restart notifications were replaced by one `modeDidChange` notification.
  The daemon synchronously drains the apply queue before terminating itself.
- CPU mode handling now uses a pure C boot/steady/leaving state model. Host
  tests cover fresh off, warmup, four restore passes, no-controller waiting,
  fullPower-to-off, and restore cancellation on another mode.
- `InsulationSoonGeneration` reads and writes now occur on the apply queue.
- Final rootless rebuild and package verification passed.
- First independent review identified upgrade-time cleanup as a failure mode;
  `prerm` now runs only for remove/deconfigure, skips upgrade, reports cleanup
  failure without blocking removal, and has executable behavior tests.
- Second independent implementation review found no P0. Its cleanup-failure
  P1 was closed by the prerm retry/warning behavior. Added the requested CPU
  coverage for full-to-low, low-to-off, and old-process/new-process restore.
- All local tests, source checks, rootless build, and package extraction checks
  pass.
- Source commit: `470b2ed7ed85f17aa0f1c17db447c0526c8ff009`.
- Pushed branch: `public-test/insulation/0.1.37-clean3`.
- macOS Actions run `29352313379` passed rootless and roothide jobs.
- Full log scan: zero incompatible-arm64e warnings, zero compiler errors, zero
  failed-build markers. The 16 `-multiply_defined is obsolete` warnings are
  linker-option deprecations, not ABI warnings.
- Cloud package verifier passed both artifacts. Retired runtime/restart
  notification strings are absent; ordered mode notification and executable
  `prerm` are present.
- Rootless SHA256: `be3d964b5e456f4b3833602f583cbf608a554b1b98d9a75a8341f645136d2374`.
- Roothide SHA256: `acc743f3aaf54452d151c1e96ad4e81ca8b88fbde80628491355ea6d886c1c47`.

## 2026-07-15 clean3 cross-model rereview

- Review remained fixed to baseline `446e813b74fe426963e84ccb8efab8f2659f90de`
  and implementation `470b2ed7ed85f17aa0f1c17db447c0526c8ff009`.
- Valid independent reviews and direct source tracing agree that direct apply
  invalidating `InsulationSoonGeneration` is a P1 scheduler/caller-composition
  defect. Only Soon scheduling or explicit cancellation may advance it.
- Main review and the second complete independent review classify removal as a
  P0 release blocker: cleanup can be undone by old/respawned injected code, and
  `prerm` can delete the helper after cleanup failure because it always exits
  zero.
- The SIGSTOP proposal was rejected: a process stopped at an arbitrary point can
  retain SCPreferences/POSIX locks needed by the external cleanup helper.
- Rapid `modeDidChange` was downgraded to P2 restart churn. Successor constructor
  replay should converge to the latest persisted mode; no correctness debounce
  is planned for clean4.
- Cloud evidence has a false-positive hole: missing `rg` is treated as a
  successful absence assertion by the mode-notification contract test.
- Clean4 design is recorded in `docs/clean4-lifecycle-plan.md`: shallow shared
  removal guard, persistent nonce marker, apply-queue quiescence, acknowledged
  PID exit, disabled/pass-through hooks, verified nine-key cleanup, fail-closed
  `prerm`, and best-effort post-removal daemon replacement.
- No production source was changed in this rereview.

## 2026-07-15 clean4 lifecycle implementation

- Branch created from `86bbc6e9ae17a0e470ef37db63642255cb8b43f9`:
  `fix/insulation-0.1.37-clean4-lifecycle`.
- Fixed the clean3 absence-test false positive by replacing the `rg` dependency
  with a checked `grep` search that distinguishes no match from search failure.
- Added pure C `InsulationApplySchedule` and scheduler/caller composition tests.
  Direct apply preserves the active Soon batch; only a new Soon batch or named
  cancellation advances generation. The constructor/CommonProduct/controller
  sequence now drains restore ownership and reaches steady off.
- Added a persistent scheme-resolved removal marker, fresh nonce acknowledgment,
  acknowledged-PID exit proof, atomic process-local disabled latch, and CLI
  actions for prepare, native reset, and successful-install marker clearing.
- Removal notification handling latches disabled before synchronizing on the
  apply queue, cancels Soon work, clears pending/coalesced work, resets controller
  ownership, writes nonce + PID acknowledgment, and terminates the daemon.
- Both constructors honor the marker. The ObjC constructor keeps only the
  removal observer active and immediately acknowledges/terminates, so a launchd
  replacement cannot replay hooks and a failed removal remains retryable.
- Runtime hooks, CommonProduct/ThermalManager paths, thermal plist patching, and
  low-level SCPreferences/Darwin-pressure writes now pass through or no-op while
  removal is latched.
- Native reset now reopens `OSThermalStatus.plist` and verifies all nine owned
  keys are absent. `prerm` fails closed on prepare/reset failure; upgrade skips
  the transaction; `postinst` clears the marker before restart; executable
  `postrm` restarts only after actual payload removal.
- Added parser, protocol, removal-script, disabled-path inventory, and package
  verification tests. All host tests, ObjC source checks, shell contracts, and
  `git diff --check` pass.
- First tool build exposed Clang auto-module contamination because the pure C
  protocol header lived under the private `insulationC` umbrella module. Moving
  the header beside its C source kept the seam pure and fixed the tool build.
- Local rootless arm64 compile/package smoke passed. Extracted package version is
  `0.1.37`; `postinst`, `prerm`, and `postrm` are executable; lifecycle strings
  exist in the payload; rejected process-control strings are absent; package
  verifier passes. Local package SHA256:
  `88783c7a2fc7f3d00d8889c48ba83e22b2adde2edb4d3e2317c0029ccef007ec`.
- Independent spec review found two final pass-through omissions in
  `ThermalManagerDimmingPatch.m`: `PackagePowerCC.initWithParams:` lacked an
  explicit removal branch, and `getPackagePowerZoneMetric` was inconsistent
  with its sibling getters. Contract tests were made red first, both hooks now
  forward original inputs/results while disabled, and the full suite/package
  smoke passed again.
- Local package is compile evidence only. Roothide/arm64e still requires macOS
  cloud build and incompatible-arm64e log scan before any delivery.
- Final pre-commit rerun passed shell syntax, ObjC source checks, all host/state/
  lifecycle contract tests, `git diff --check`, a clean rootless package build,
  and extracted-package verification. Fresh local rootless SHA256:
  `321a2cccfad11f7f5bd284885aa143a91d99c82f2b3d117638de827c93e2ba70`.
