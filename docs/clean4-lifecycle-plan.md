# Insulation 0.1.37 clean4 lifecycle plan

Review baseline: `446e813b74fe426963e84ccb8efab8f2659f90de`

Reviewed implementation: `470b2ed7ed85f17aa0f1c17db447c0526c8ff009`

This document is the clean4 lifecycle source of truth. The working implementation
on `fix/insulation-0.1.37-clean4-lifecycle` is validated against these requirements;
remaining device/package-manager facts stay explicitly listed below.

## Review verdict

### P0: removal is not a closed transaction

`layout/DEBIAN/prerm` currently removes the nine owned SCPreferences keys,
then calls `killall thermalmonitord`, ignores cleanup/restart failures, and
always exits zero.

That ordering permits both of these executions:

1. an apply already queued in the old daemon rewrites keys after cleanup; or
2. launchd starts another injected daemon while the payload and full-power
   preferences still exist, and constructor replay recreates the keys.

If cleanup fails but removal continues, the package manager can delete the only
bundled cleanup tool while persistent thermal overrides remain. This blocks a
clean3 release.

### P1: direct apply cancels the restore events it needs

`InsulationExecutePuppetEventWithSource` increments
`InsulationSoonGeneration`. A normal direct apply therefore invalidates every
outstanding delayed apply.

A valid fresh-process/off-mode sequence is:

1. constructor schedules four delayed applies at generation 1;
2. `CommonProduct.initProduct` directly applies, advances the generation, and
   can arm `pendingRestoreCount=4` before a controller exists;
3. constructor callbacks reject generation 1;
4. controller capture and its 0.5-second replay consume only part of the
   pending restore count; and
5. no later apply is guaranteed, so `InsulationCPURestoreActive()` can remain
   true indefinitely in off mode.

The existing pure state-machine tests do not compose the scheduler and its real
callers, so they cannot detect this failure.

### P1 verification defect: missing `rg` is treated as success

`scripts/test-clean3-mode-notification-contract.sh` uses `if ! rg ...` for an
absence assertion. Exit 127 (`rg` missing) is interpreted as “string absent”,
so the test prints success without performing the scan. The cloud build exposed
this exact false positive.

### P2: rapid mode changes can cause restart churn, not a proven convergence failure

Mode writers atomically replace the preferences file before posting
`modeDidChange`. The callback drains a synchronous apply before SIGTERM; if a
later notification is lost while the process exits, the successor constructor
rereads the latest persisted mode.

This relies on the same launchd restart and constructor execution behavior the
current product already requires. A process-local debounce disappears on the
first restart and is not a correctness boundary. Do not add one in clean4.

## Clean4 hypothesis

A small shared removal guard, combined with apply-queue quiescence and a
nonce-validated removal handshake, can make removal fail closed without moving
all apply and hook ownership into a new lifecycle coordinator.

The guard is deliberately shallow. It owns only:

- the persistent removal marker and acknowledgment identity;
- an atomic process-local disabled latch; and
- the prepare-for-removal handshake.

`InsulationPowerHelper`, runtime hooks, and native-state cleanup retain their
current ownership.

## Required design

### 1. Fix scheduler ownership

- Remove generation advancement from
  `InsulationExecutePuppetEventWithSource`.
- Only `InsulationExecutePuppetEventSoonWithSource`, or a named explicit
  cancellation operation, may advance `InsulationSoonGeneration`.
- The removal callback uses the explicit cancellation operation on the apply
  queue.
- A delayed callback checks both generation and the removal-disabled latch at
  execution time.
- Pending/coalesced apply work checks the latch on every loop, not only when it
  is enqueued.

### 2. Use a persistent, scheme-resolved removal marker

Use one canonical logical marker under the mobile preferences area, resolved by
exactly the same rootless/roothide path mechanism in the daemon and CLI. Do not
use `/var/run`; it is not a reboot-persistent transaction record.

The marker contains a fresh nonce. A stale acknowledgment cannot satisfy a new
removal attempt.

A successful future `postinst` clears the marker only after the new payload is
fully installed, then restarts `thermalmonitord`. Upgrade `prerm` does not create
the marker or clean user/runtime state.

### 3. Prepare-for-removal handshake

For `remove` and `deconfigure`:

1. The bundled helper atomically creates the marker with a fresh nonce and
   clears any stale acknowledgment.
2. It establishes the acknowledgment wait before posting a dedicated Darwin
   prepare-for-removal notification.
3. The daemon callback synchronizes onto `InsulationApplyQueue`.
4. On that queue it atomically latches disabled state, explicitly cancels the
   delayed generation, clears pending/coalesced work, and resets process-local
   restore ownership.
5. It writes an acknowledgment containing the marker nonce and daemon PID, then
   posts the acknowledgment notification.
6. The daemon terminates itself with SIGTERM.
7. The helper validates the nonce and proves that the acknowledged PID exited
   before native cleanup begins.

If notification delivery, nonce validation, or PID-exit proof fails, `prerm`
returns nonzero. A timeout is a failure signal, not permission to continue.

A replacement daemon that sees the marker must skip both hook-installing
constructors and constructor replay. Correctness therefore does not require the
prepare notification to be delivered to a replacement process.

### 4. Disabled means pass-through

The process-local latch is atomic because hooks can run outside the apply queue.
When latched:

- direct apply, delayed apply, pending/coalesced apply, constructor replay, and
  apply/mode callbacks do no work;
- `CommonProduct.initProduct` does not capture or schedule;
- controller update hooks call originals without capture or self-heal replay;
- all MitigationController setter hooks forward the original arguments;
- CommonProduct pressure/action hooks call originals without simulation or
  suppression;
- the NSDictionary thermal-plist hook returns the original dictionary;
- ThermalManagerDimmingPatch hooks return/call originals without configuration
  replacement, pressure capping, suppression, watchdog changes, or power
  parameter patching; and
- low-level SCPreferences and Darwin-pressure write helpers reject non-cleanup
  writes as defense in depth.

Probe-only getters that already return original values need no behavior change.

Both hook-installing constructors must check the persistent marker before
installation:

- `Sources/insulationObjC/TweakInit.m`
- `Sources/insulationC/ThermalManagerDimmingPatch.m`

### 5. Cleanup and package-script failure semantics

After the acknowledged daemon PID has exited:

1. run the shared nine-key native reset;
2. reopen/re-synchronize SCPreferences and verify that all nine keys are absent;
3. retry only bounded, idempotent cleanup attempts; and
4. return nonzero if any key remains or the API reports failure.

On failure, retain the marker and package payload so the tweak stays disabled
and the cleanup tool remains available for retry/repair.

After payload deletion, `postrm` performs a best-effort SIGTERM so any inert
process that mapped the old dylib is replaced by a pristine process. The marker
remains after uninstall; only a successful later install clears it.

## Rejected designs

- **Current cleanup then killall:** cleanup can be undone by old or respawned
  injected code.
- **Warning plus exit zero:** can delete the only cleanup tool while native keys
  remain.
- **Blind sleep:** does not prove queue quiescence or process exit.
- **Marker only:** an already-running process does not automatically observe it,
  and in-flight work can pass an earlier check.
- **SIGSTOP then cleanup then SIGKILL:** SIGSTOP can freeze the daemon while it
  owns an SCPreferences/POSIX lock; the cleanup helper can then block on the
  stopped lock owner. No source or device evidence establishes this as safe.
- **Unverified launchctl bootout/bootstrap:** label, bootstrap domain, rootless
  permissions, and recovery behavior are not established on the target matrix.
- **Changing the user mode to off:** destroys user configuration and still does
  not prove cleanup.
- **Process-local mode debounce:** does not survive the first restart and is not
  needed for eventual convergence.
- **Large lifecycle-coordinator rewrite:** unnecessary. A shared guard is needed,
  but apply, hook, and prefs ownership should not migrate in clean4.

## Success criteria

- A fresh off-mode process reaches `InsulationCPUPhaseSteady`; no valid caller
  sequence can strand `pendingRestoreCount`.
- The latest persisted mode converges before process exit or through successor
  constructor replay.
- Successful remove/deconfigure leaves all nine owned keys absent.
- No hooked process can rewrite native state after verified cleanup.
- Cleanup failure blocks normal removal and retains the marker and helper.
- Upgrade neither cleans state nor changes user preferences.
- Repeated cleanup, repeated prepare, stale acknowledgment, and no-key cleanup
  are safe and deterministic.
- Rootless and roothide resolve the same per-scheme marker/ack path used by both
  the daemon and helper.

## Independent failure signals

- A direct apply still changes `InsulationSoonGeneration`.
- Any delayed or pending block can execute without checking disabled state at
  execution time.
- Either hook constructor can install while the persistent marker exists.
- Any mutating hook lacks pass-through behavior when disabled.
- `prerm` can return zero without nonce acknowledgment, acknowledged-PID exit,
  and verified nine-key absence.
- Cleanup failure deletes or makes the cleanup helper unavailable.
- Upgrade creates the marker or removes native keys.
- A test treats command-not-found as a successful absence assertion.

## Evidence plan

1. Add a deterministic scheduler/caller composition test reproducing the
   constructor → CommonProduct → controller-capture sequence.
2. Add removal protocol tests for success, timeout, stale acknowledgment,
   cleanup failure, retry, upgrade, and idempotence.
3. Add an explicit source inventory test for both constructors and every
   mutating hook/write path listed above.
4. Make forbidden-string tests fail fast when their search tool is missing, or
   replace `rg` with a guaranteed dependency.
5. Run all host tests and shell syntax checks.
6. Build and inspect rootless and roothide packages, including `prerm`, `postrm`,
   marker path strings, executable helper, Mach-O slices, and forbidden strings.
7. Scan cloud logs for compiler failures and incompatible arm64e ABI warnings.
8. Perform an independent post-implementation review before delivery.

## Platform facts still requiring device or package-manager evidence

- The canonical marker path resolves identically for each daemon/helper pair on
  rootless and roothide.
- SIGTERM and launchd replacement behavior for `thermalmonitord` on every target
  iOS version.
- Exact `prerm` → payload deletion → `postrm` behavior in each supported package
  manager.

These unknowns must be tested. They are not reasons to replace proof with a
blind delay or an undocumented `launchctl` assumption.
