# Progress

## 2026-07-19 - Decision probe Phase 1

- Baseline: `release/0.1.40-repair-fix` at `ca2072a50caac27411a49ef4365e5795ee6549b1`.
- Hypothesis: the existing MitigationController setter, update, and target-getter hooks can identify whether thermalmonitord is still issuing restrictive decisions while the device downclocks; a kernel/firmware cause remains outside this probe's evidence boundary.
- Success: an opt-in cloud-built probe writes bounded, atomic snapshots containing hook-install status, method ABI inventory, update counts, and original/patched setter values without changing return values or default package contents.
- Independent failure signals: no snapshot after thermalmonitord startup; required hooks reported missing; probe source or markers present in a default build; write cadence exceeds the coalesced interval; any IOKit, call-stack, notify, or frequency-read instrumentation enters the diagnostic path.
- Evidence plan: source safety checks, host tests, local rootless/roothide compile smoke checks, default/probe binary marker scans, macOS CI logs with no incompatible arm64e warnings, extracted package inspection, and SHA-256 verification.
- Resume hint: implement the diagnostic-only writer and method inventory, add CI input/static checks, then build `0.1.42+decisionprobe1` through the macOS workflow.

## 2026-07-20 - Decision probe Phase 2 direct-write observation

- Baseline: `release/0.1.40-repair-fix` at `f38d11fb5a7dfc3e35f1e7bf4961ba8ab40948b1`; existing untracked Phase 1 docs/progress files were preserved.
- Device evidence: pid `22507` remained alive from 00:47 through 10:30; CPU/DVD1/GPU ceiling hooks intercepted 102 restrictive calls each, but the user still reported occasional downclocking.
- Ranked hypothesis: an unobserved MitigationController direct-write path may bypass the existing ceiling setters. The class inventory exposes `setDieTempControllerProperty:level:scaleToFixedPoint:` and `setServiceProperty:key:value:scaleToFixedPoint:`; neither was previously hooked.
- Success: an opt-in probe build records install status, call count, latest timestamp, unchanged arguments, and the original service-property return value for both selectors without changing production behavior.
- Independent failure signals: either selector ABI fails to compile; a wrapper records before calling the original; any argument or return value changes; direct-write hooks enter default builds; records grow without bound; no direct-write call aligns with a user-observed downclock.
- Evidence plan: static pass-through checks, ObjC source checks, probe-enabled package compile, default-build marker exclusion, cloud arm64e build with zero incompatible ABI warnings, then device timestamp correlation through `directCalls`/`lastDirectCall`.
- Resume hint: validate locally, bump the diagnostic build suffix to `decisionprobe2`, run macOS workflow with `decision_probe=true`, inspect the artifact, and deliver only the cloud-built roothide package.

## 2026-07-20 - Decision probe Phase 2 cloud artifact

- Commit: `d6aed21` (`probe: observe MitigationController direct-write paths (Phase 2)`).
- Cloud workflow: `doimty/test` run `29717551064`, macOS-14 matrix succeeded for rootless and roothide.
- Cloud log scan: no `incompatible arm64e` warnings and no build error/fatal/failed markers.
- Delivered artifact: `com.be-huge.insulation_0.1.42+decisionprobe2_iphoneos-arm64e.deb`.
- Roothide SHA256: `a431f1e546257df2f1495c1df917bd554402f296a68428f9ba8cce618a588858`.
- Package verification: control architecture `iphoneos-arm64e`; tweak, preferences, Control Center bundle, and CLI all contain `ARM64 E USR00`; direct-write probe markers are present; CPMS probe markers are absent.
- Device validation target: after installing and restarting thermalmonitord, inspect `directCalls`, `lastDirectCall`, and hook-install records, then correlate timestamps with the next user-observed downclock.

## 2026-07-20 - Decision probe Phase 3 manual marker

- Baseline: `release/0.1.40-repair-fix` at `d6aed219b63c7cfcca6bfddea72924c0d38c2ee9`.
- Rejected experiment: a 10-second Darwin thermal-pressure ring monitor was implemented and locally compiled, then removed before delivery. Independent reviews found that `thermalpressurelevel` primarily echoed Insulation's own state writes, `thermalstatus` was not independently read, and neither channel could identify the sender or distinguish kernel/SoC, powerd, display, or scheduler causes.
- User evidence: A15 normally reports 3240 MHz; under a deliberate high-temperature stress test above roughly 40°C it falls to fixed 2015/1584 MHz levels for several minutes and automatically recovers. The agreed safety boundary is diagnosis only; no bypass of hardware thermal/current protections.
- Hypothesis: an exact user marker aligned with the external frequency display can determine whether covered thermalmonitord setters remain patched to 65000 at the observed downclock. If they do, the cause is downstream of the covered user-space decision paths.
- Success: `ins probe-mark downclock` posts a dedicated diagnostic notification; only a probe-enabled thermalmonitord records wall and monotonic time, snapshots setter/direct/update state, appends bounded marker/setter timelines, and immediately writes the plist.
- Independent failure signals: thermal pressure/status monitoring re-enters the probe; default tweak binary contains the marker listener; marker or setter history grows without bound; the command changes mode or restarts thermalmonitord; marker output claims a specific hardware component without independent evidence.
- Evidence plan: host CLI parser tests, static gate/boundedness checks, probe and default builds, binary forbidden/presence scans, package verification, independent review, then macOS roothide CI before delivery.

## 2026-07-22 - Decision probe Phase 6 IOKit correlation

- Baseline: `release/0.1.40-repair-fix` at `006470f0b1b008f23f3f24b134540b05f8557947`; the rejected `public-test/extreme/iokit1` active-write branch is not an implementation base.
- Hypothesis: at least one pass-through call to `setDieTempControllerProperty:level:scaleToFixedPoint:` or `setServiceProperty:key:value:scaleToFixedPoint:` occurs close enough to a user-marked downclock to identify a concrete `property` or `service`/`key` for a narrower follow-up experiment.
- Success: a probe-only, thermalmonitord-only build records a bounded direct-call timeline with wall and monotonic timestamps, unchanged arguments, and unchanged service-property results; `ins probe-mark downclock` freezes that timeline in the marker snapshot.
- Independent failure signals: no direct-write event near the marker; only unrelated properties appear; any wrapper changes an argument or return value; either probe configuration fails to compile; hooks install more than once; probe markers or sources enter the default binary; the tweak injects into `powerd` or `hids`.
- Ablation expectation: with `INSULATION_PROBE_ENABLED=0`, both private selectors and all marker/timeline strings are absent from the tweak binary and production behavior matches the baseline; with it set to `1`, only observation and bounded snapshot writes are added.
- Evidence plan: fail-first static contract checks, source review, local rootless default/probe builds, binary marker scans, package inspection, then macOS roothide CI with no incompatible arm64e warnings before device delivery.
- Resume hint: add the bounded direct-call timeline and dual-config build gate, verify locally, then build `0.1.42+decisionprobe6` with `decision_probe=true`.
- Local implementation evidence: source/static checks and CLI tests passed; rootless default and probe configurations both compiled and packaged from the final source state; the reusable package verifier confirmed probe markers absent/present as expected, known rejected Phase 4/5 global probe markers absent, and an exact thermalmonitord-only substrate filter.
- Local compile-only artifacts: default SHA-256 `6b97f7aa4c9bf878013b0d0ca77c294e8c86cb2da36fdcf06434954cb2f2a4d4`; probe SHA-256 `912772d1cdbe4c3efa306147794eae200b4482dca02fe0c289598a74bce03d24`. Linux linkage emitted 16/17 known incompatible arm64e ABI warnings, so neither local package is deliverable; roothide delivery remains cloud-build-only.
- Review closure: package verification now parses the substrate plist and requires `Filter.Executables == ["thermalmonitord"]`; source/package gates cover the known Phase 4/5 install and snapshot entrypoints; pending-ingress capacity, pruning, and persisted dropped-count checks are structurally bound to the recorder/drain function bodies.
