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
