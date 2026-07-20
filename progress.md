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
