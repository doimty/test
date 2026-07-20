# Decision Probe Phase 1

## Scope

This diagnostic build observes the existing thermalmonitord decision path. It does not attempt to observe or modify kernel, CLPC firmware, PMIC, or actual CPU frequency behavior.

The probe records:

- MitigationController hook installation results.
- Direct methods and Objective-C type encodings for MitigationController and non-NSObject superclasses.
- Existing update call counts and object-change status.
- Existing setter and target-getter original/patched values.
- Constructor and apply lifecycle counters.

## Constraints

- Default builds keep `INSULATION_PROBE_ENABLED=0` and exclude `InsulationProbe.m`.
- Probe hooks call the same original implementations with the same values selected by the production code.
- Snapshot writes are serialized, coalesced, atomic, and limited to one successful path per flush.
- No global IOKit interception, stack unwinding, Darwin notification logging, sysctl frequency reads, initializer hook, or new control-loop calls.
- Phase 2 adds pass-through observation of MitigationController's existing `setDieTempControllerProperty:level:scaleToFixedPoint:` and `setServiceProperty:key:value:scaleToFixedPoint:` methods. Both call the original implementation first with unchanged arguments; the latter returns the original result unchanged.
- Direct-write observations retain counters plus only the latest bounded record per selector. They do not accumulate an unbounded event history.
- A high patched target alongside an externally observed downclock is inconclusive about kernel or firmware causality.

## Device Evidence

After installing the cloud-built diagnostic package, restart thermalmonitord, wait for the snapshot, reproduce the charging-temperature downclock, and collect `com.be-huge.insulation-decision-probe.plist`. The external frequency observation and the snapshot should use matching wall-clock timestamps.

For Phase 2, inspect `directCalls` and `lastDirectCall`. A direct-call timestamp aligned with an externally observed downclock identifies an active MitigationController direct-write path; absence of a call during the same interval falsifies these two selectors as the bypass for that episode.

## Phase 3 Manual Downclock Marker

Phase 3 adds a manual marker only. It deliberately does not monitor the shared `com.apple.system.thermalpressurelevel` or `com.apple.system.thermalstatus` channels: Insulation itself writes the former, notification state has no sender identity, and delayed reads can lose transient values.

When an external observer shows the A15 dropping from 3240 MHz to 2015/1584 MHz, run:

```sh
ins probe-mark downclock
```

The probe-only thermalmonitord listener records wall-clock and monotonic timestamps, snapshots current setter/direct-call/update aggregates, and immediately writes the plist. Setter events are also retained in a bounded 96-entry timeline so events immediately before and after the marker can be aligned after waiting five seconds and collecting the plist.

Interpretation is intentionally narrow:

- Setter targets still patched to 65000 around the marker, with no direct-write activity: the observed limit is downstream of the covered thermalmonitord decision paths. This is consistent with CLPC/SoC/PMIC protection but does not identify a specific component.
- A restrictive unpatched setter or an active direct-write event around the marker: continue investigation on that user-space path.
- Missing or stale evidence: improve the feedback loop; do not infer a hardware cause.

This phase diagnoses only. It does not bypass CLPC, SoC, PMIC, die-temperature, current, or emergency thermal protections.
