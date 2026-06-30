
## [LRN-20260528-004] correction

**Logged**: 2026-05-28T17:29:00+08:00
**Priority**: high
**Status**: active
**Area**: insulation backboardd safety

### Summary
Do not ship backboardd injection in the default insulation build. Even narrower/delayed hooks are high-risk because backboardd startup issues can cause black screen or boot/session instability.

### Details
The user explicitly expressed concern that backboardd is not acceptable due to startup risk. Future dimming experiments should stay off the main thermal-tunes default build or be packaged separately as an experimental branch/artifact.

### Suggested Action
Revert backboardd injection from default branch. Keep stable thermalmonitord-only builds as default; investigate alternative non-backboardd routes or a clearly-labeled experimental package only if requested.

### Tags
correction, backboardd, safety, insulation

---

## [LRN-20260530-001] correction

**Logged**: 2026-05-30T10:28:00+08:00
**Priority**: high
**Status**: active
**Area**: insulation CPU thermal tuning

### Summary
For Insulation CPU low-power simulation, avoid reintroducing the old heavy paths that either made the phone unusably slow or prevented full recovery.

### Details
Historical commits show two failure modes: `0207a0c` used simulated low power with `powerSaveActive(true)`, CPU level 4, and 50% power targets, which was too aggressive; later recovery attempts that wrote CPU power targets/ceilings were harder to unwind. Safer behavior is the `55a1c29` direction: only lock a light CPU mitigation level, keep system power save false, avoid CPU power target locks, and use repeated restore passes to clear powerSave/CPULevel after disabling.

### Suggested Action
When the user asks for actual low-power simulation, `powerSaveActive(true)` is part of the requested behavior. Avoid the old heavy combo by mapping to level1 only, not manually forcing 50% low-power target/ceiling/zone targets, aligning restore pass count with scheduled delayed events, and during restore clearing powerSave/CPULevel before and after the original `updateCPU()` call.

### Tags
correction, insulation, cpu-frequency, thermalmonitord, restore

---

## [LRN-20260531-001] correction

**Logged**: 2026-05-31T01:30:00+08:00
**Priority**: high
**Status**: pending
**Area**: tweak

### Summary
Insulation low-power simulation using only powerSaveActive(true) + CPU level1 + 100% target was too conservative and did not affect low-power frequency in real testing.

### Details
User tested build 0333674 and reported low-power frequency was ineffective. For actual effect, the tweak likely needs a moderate CPU power target cap in addition to powerSaveActive and CPULevel, while retaining aggressive multi-pass restore.

### Suggested Action
Use a middle setting such as CPU level2 + 70% target, actively set CPULowPowerTarget/CPUPowerCeiling/CPUPowerZoneTarget while enabled, and restore with high targets/floor reset while disabled.

### Metadata
- Source: user_feedback
- Related Files: Sources/insulation/Tweak.x.swift, Sources/insulation/utils/IPowerHepler.swift
- Tags: insulation, cpu, low-power, restore

---

## [LRN-20260531-002] correction

**Logged**: 2026-05-31T07:56:00+08:00
**Priority**: high
**Status**: active
**Area**: insulation CPU thermal tuning

### Summary
Low-power frequency simulation did work in the first May 31 build; test confusion came from leaving the "disable thermal throttling" switch enabled.

### Details
The user confirmed the first May 31 low-power build can trigger low-power-mode CPU frequency. The real bug is interaction with `thermalDisableMitigationsEnabled`: when this switch is enabled after low-power mode, CPU frequency may not return to full because the hook path wrote/kept bad CPU target state instead of explicitly restoring unrestricted targets.

### Suggested Action
Treat `thermalCPULimitEnabled` and `thermalDisableMitigationsEnabled` as mutually exclusive modes. When disabling mitigations, write full CPU target/ceiling/zone target and clear power-save/CPU level. Do not interpret low-power no-effect reports unless the advanced mitigation-disabling switch state is known.

### Metadata
- Source: user_feedback
- Related Files: Sources/insulation/Tweak.x.swift, Sources/insulation/utils/IPowerHepler.swift
- Tags: insulation, cpu, low-power, disable-mitigations, restore

---

## [LRN-20260531-003] correction

**Logged**: 2026-05-31T08:06:00+08:00
**Priority**: high
**Status**: active
**Area**: insulation CPU low-power tuning

### Summary
The `level2 + 70% CPU target` low-power build is too aggressive and can clamp CPU around 600 MHz, causing severe lag.

### Details
User tested the build from run 26698191104 / commit 155f11e and reported it was not normal Low Power Mode frequency; it pressed CPU down around 600 MHz and made the device nearly unusable.

### Suggested Action
Do not manually cap `CPULowPowerTarget`, `CPUPowerCeiling`, or `CPUPowerZoneTarget` for the low-power simulation path. Use a softer system-like route: `powerSaveActive(true)` + CPU level1, with CPU target percent left at 100%. Keep the full-target restore fix for `thermalDisableMitigationsEnabled`.

### Metadata
- Source: user_feedback
- Related Files: Sources/insulation/Tweak.x.swift, Sources/insulation/utils/IPowerHepler.swift
- Tags: insulation, cpu, low-power, performance, restore

---
