#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
section() { printf '\n== %s ==\n' "$1"; }
check_zero() {
  local label="$1" count="$2"
  if [[ "$count" == "0" ]]; then
    echo "OK: $label = 0"
  else
    echo "FAIL: $label = $count" >&2
    fail=1
  fi
}
check_nonzero() {
  local label="$1" count="$2"
  if [[ "$count" != "0" ]]; then
    echo "OK: $label = $count"
  else
    echo "FAIL: $label = 0" >&2
    fail=1
  fi
}

section "ObjC source files"
main_objc_files=$(find Sources/insulationObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) | sort)
main_c_files=$(find Sources/insulationC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) ! -name 'Tweak.m' | sort)
prefs_objc_files=$(find InsulationPrefs/Sources/InsulationPrefsObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) | sort)
prefs_c_files=$(find InsulationPrefs/Sources/InsulationPrefsC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) | sort)
check_nonzero "main ObjC files" "$(printf '%s\n' "$main_objc_files" | sed '/^$/d' | wc -l | tr -d ' ')"
check_nonzero "prefs ObjC files" "$(printf '%s\n' "$prefs_objc_files" | sed '/^$/d' | wc -l | tr -d ' ')"

section "No Swift/Orion references"
objc_refs=$(grep -RInE 'Orion|orion_init|ClassHook|import Swift|IPowerHepler|IDictHepler|IFileManager' Sources/insulationObjC InsulationPrefs/Sources/InsulationPrefsObjC || true)
if [[ -z "$objc_refs" ]]; then
  echo "OK: no Swift/Orion references in ObjC code"
else
  echo "$objc_refs" >&2
  fail=1
fi

section "No Orion init in C sources"
if printf '%s\n' "$main_c_files" | grep -q 'Sources/insulationC/Tweak.m'; then
  echo "FAIL: should not include Orion Tweak.m" >&2
  fail=1
else
  echo "OK: Orion Tweak.m excluded"
fi

section "Private headers"
for header in \
  InsulationPrefs/Sources/InsulationPrefsC/include/Preferences/PSListController.h \
  InsulationPrefs/Sources/InsulationPrefsC/include/Preferences/PSSpecifier.h; do
  if [[ -f "$header" ]]; then
    echo "OK: $header"
  else
    echo "FAIL: missing $header" >&2
    fail=1
  fi
done

section "Required hook selectors"
required_selectors=(
  'dictionaryWithContentsOfFile:'
  'initProduct:'
  'tryTakeAction'
  'handleMCSThermalPressure'
  'simulateLightThermalPressure'
  'updatePowerzoneTelemetry'
  'setPowerSaveActive:'
  'setCPULevel:'
  'setCPULowPowerTarget:'
  'setCPUPowerCeiling:fromDecisionSource:'
  'setCPUPowerCeiling:forDVD1Contributor:'
  'setCPUPowerFloor:fromDecisionSource:'
  'setCPUPowerZoneTarget:'
  'setDVD1Level:'
  'setGPUPowerCeiling:fromDecisionSource:'
  'setGPUPowerFloor:fromDecisionSource:'
  'setGPUPowerZoneTarget:'
  'setSGXLevel:'
  'setMaxGraphicsDrivePowerTarget:'
  'setPackagePowerCeiling:fromDecisionSource:'
  'setPackagePowerFloor:fromDecisionSource:'
  'setMaxPackagePower:'
  'setPackageLowPowerTarget'
  'setPackagePowerZoneTarget'
  'updateCPU'
  'updateGPU'
  'updatePackage'
)
hook_sources=(
  Sources/insulationObjC/InsulationRuntimeHooks.m
  Sources/insulationC/ThermalManagerDimmingPatch.m
)
for selector in "${required_selectors[@]}"; do
  if grep -Fq "@selector($selector)" "${hook_sources[@]}"; then
    echo "OK: $selector"
  else
    echo "FAIL: missing selector $selector" >&2
    fail=1
  fi
done

section "Targeted CPMS probe safety"
python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
makefile = (root / "Makefile").read_text()
runtime = (root / "Sources/insulationObjC/InsulationRuntimeHooks.m").read_text()
probe = (root / "Sources/insulationObjC/InsulationCPMSProbe.m").read_text()
errors = []

checks = {
    "probe defaults off": "INSULATION_CPMS_PROBE_ENABLED ?= 0" in makefile,
    "disabled probe source is excluded": "! -name 'InsulationCPMSProbe.m'" in makefile,
    "runtime install is compile-gated": re.search(
        r"#if INSULATION_CPMS_PROBE_ENABLED\s+InsulationCPMSProbeInstall\(\);\s+#endif",
        runtime,
    ) is not None,
    "max selector is exact": 'sel_registerName("getMaxPowerForComponent:")' in probe,
    "min selector is exact": 'sel_registerName("getMinPowerForComponent:")' in probe,
    "return ABI is checked": "InsulationCPMSProbeBaseType(returnType) == 'I'" in probe,
    "self ABI is checked": "InsulationCPMSProbeBaseType(selfType) == '@'" in probe,
    "selector ABI is checked": "InsulationCPMSProbeBaseType(selectorType) == ':'" in probe,
    "argument ABI is checked": "InsulationCPMSProbeBaseType(componentType) == 'i'" in probe,
    "argument count is checked": "argumentCount == 3" in probe,
    "initial snapshot is asynchronous": "dispatch_after(dispatch_time(DISPATCH_TIME_NOW" in probe and "dispatch_sync(InsulationCPMSProbeQueue()" not in probe,
    "class lookup retries are absolute and bounded": re.search(
        r"InsulationCPMSProbeRetryOffsets\[\] = \{\s*0\.0,\s*0\.25,\s*1\.0,\s*3\.0\s*\}",
        probe,
    ) is not None and "attemptCount" in probe,
    "write results are recorded": "InsulationCPMSProbeWriteSnapshotData" in probe and "writeResults" in probe and "snapshot write failed" in probe,
    "partial install history is retained": "everInstalled" in probe and "InsulationCPMSProbeMaxEverInstalled" in probe,
}
for label, condition in checks.items():
    if not condition:
        errors.append(label)

for selector in ("getMaxPowerForComponent", "getMinPowerForComponent"):
    wrapper = re.search(
        rf"static unsigned Insulation_CPMSProbe_{selector}\([^{{]+\) \{{(?P<body>.*?)\n\}}",
        probe,
        re.DOTALL,
    )
    if wrapper is None:
        errors.append(f"{selector} wrapper is missing")
        continue
    body = wrapper.group("body")
    original_call = f"Orig_CPMSProbe_{selector}(self, _cmd, component)"
    if original_call not in body:
        errors.append(f"{selector} does not call the original implementation")
    if "return original;" not in body:
        errors.append(f"{selector} does not return the original result")
    record_position = body.find("InsulationCPMSProbeRecord")
    if record_position >= 0 and body.find(original_call) > record_position:
        errors.append(f"{selector} records before calling the original implementation")

install_method = re.search(
    r"static BOOL InsulationCPMSProbeInstallMethod\([^\{]+\) \{(?P<body>.*?)\n\}",
    probe,
    re.DOTALL,
)
if install_method is None:
    errors.append("IMP install helper is missing")
else:
    install_body = install_method.group("body")
    original_position = install_body.find("*originalOut = original;")
    replacement_position = install_body.find("method_setImplementation(method, replacement)")
    if original_position < 0 or replacement_position < 0 or original_position > replacement_position:
        errors.append("original IMP is not published before method replacement")

for forbidden in (
    "InsulationPowerMitigationsDisabled",
    "InsulationUnrestrictedPowerLimit",
    "InsulationMaxComponentPower",
    "InsulationPowerLimitValue",
):
    if forbidden in probe:
        errors.append(f"probe contains behavior-changing helper: {forbidden}")

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)
print("OK: CPMS probe is opt-in, ABI-gated, and pass-through")
PY

section "ObjC runtime risk scan"
risky_objc_refs=$(grep -RInE '__weak|objc_msgSend|performSelector|NSClassFromString|dlsym|unsafe_unretained' Sources/insulationObjC InsulationPrefs/Sources/InsulationPrefsObjC InsulationPrefs/Sources/InsulationPrefsC || true)
if [[ -z "$risky_objc_refs" ]]; then
  echo "OK: no high-risk dynamic ObjC patterns"
else
  echo "$risky_objc_refs" >&2
  fail=1
fi

kvc_refs=$(grep -RInE 'valueForKey:|setValue:forKey:' Sources/insulationObjC InsulationPrefs/Sources/InsulationPrefsObjC InsulationPrefs/Sources/InsulationPrefsC || true)
if [[ -z "$kvc_refs" ]]; then
  echo "OK: no KVC references"
elif python3 - "$kvc_refs" <<'PY'
import sys
refs = sys.argv[1].splitlines()
allowed = [
    'InsulationPrefs/Sources/InsulationPrefsObjC/RootListController.m:    NSMutableArray *specifiers = [self valueForKey:@"_specifiers"];',
]
normalized = []
for ref in refs:
    parts = ref.split(':', 2)
    if len(parts) != 3:
        normalized.append(ref)
    else:
        normalized.append(f'{parts[0]}:{parts[2]}')
sys.exit(0 if normalized == allowed else 1)
PY
then
  echo "OK: only allowed KVC reference for _specifiers"
else
  echo "$kvc_refs" >&2
  echo "FAIL: unexpected KVC references" >&2
  fail=1
fi

section "Helper API surface"
python3 - <<'PY'
import re
import sys
from pathlib import Path

headers = list(Path('Sources/insulationObjC').glob('*.h'))
impls = list(Path('Sources/insulationObjC').glob('*.m'))
header_text = '\n'.join(p.read_text() for p in headers)
impl_text = '\n'.join(p.read_text() for p in impls)

def names(pattern, text):
    return sorted(set(re.findall(pattern, text, re.M)))

header_decls = names(r'^[A-Za-z_][A-Za-z0-9_ \t\*]*\*?\s*(Insulation[A-Za-z0-9_]+)\s*\([^;]*\);', header_text)
impl_defs = names(r'^(?:static\s+)?[A-Za-z_][A-Za-z0-9_ \t\*]*\*?\s*(Insulation[A-Za-z0-9_]+)\s*\([^;]*\)\s*\{', impl_text)
missing = [name for name in header_decls if name not in impl_defs]
if missing:
    print('FAIL: declarations without implementations: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)
print('OK: all declarations have implementations')

required_static_helpers = [
    'InsulationHasPref',
    'InsulationBoolPref',
    'InsulationResetObservedPowerState',
    'InsulationRestoreFullCPU',
    'InsulationApplyCPUPerformancePreference',
    'InsulationApplyThermalTuningPreferences',
    'InsulationIntValue',
    'InsulationMaxObjectInArray',
    'InsulationLockArrayToMax',
    'InsulationAutomaticThermalPower',
    'InsulationDictionaryLooksLikeBacklight',
    'InsulationPatchBacklightDictionary',
    'InsulationRecursivelyPatchThermalObject',
    'InsulationApplyNotificationCallback',
    'InsulationRestartNotificationCallback',
]
for name in required_static_helpers:
    pattern = rf'^static\s+[A-Za-z_][A-Za-z0-9_ \t\*]*\*?\s*{name}\s*\('
    if not re.search(pattern, impl_text, re.M):
        print(f'FAIL: helper is not static: {name}', file=sys.stderr)
        sys.exit(1)
print('OK: internal helpers remain static')
PY
if [[ $? -ne 0 ]]; then
  fail=1
fi

section "Decision direct-write probe safety"
python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
runtime = (root / "Sources/insulationObjC/InsulationRuntimeHooks.m").read_text()
probe = (root / "Sources/insulationObjC/InsulationProbe.m").read_text()
tweakinit = (root / "Sources/insulationObjC/TweakInit.m").read_text()
ctl_args = (root / "Sources/insulationctl/InsulationCtlArgs.c").read_text()
ctl_main = (root / "Sources/insulationctl/main.m").read_text()
makefile = (root / "Makefile").read_text()
filter_plist = (root / "insulation.plist").read_text()
objc_probe_surface = "\n".join(path.read_text() for path in (root / "Sources/insulationObjC").glob("*.[mch]"))
errors = []
direct_call_drain = re.search(
    r"static void InsulationProbeDrainDirectCalls\(void\) \{(?P<body>.*?)\n\}\n\nvoid InsulationProbeRecordDirectCall",
    probe,
    re.DOTALL,
)
direct_call_recorder = re.search(
    r"void InsulationProbeRecordDirectCall\([^\{]+\) \{(?P<body>.*?)\n\}\n\nvoid InsulationProbeRecordHookInstall",
    probe,
    re.DOTALL,
)
marker_recorder = re.search(
    r"void InsulationProbeRecordMarker\([^\{]+\) \{(?P<body>.*?)\n\}\n\n#else",
    probe,
    re.DOTALL,
)

checks = {
    "direct-write install is probe-gated": re.search(
        r"#if INSULATION_PROBE_ENABLED\s+InsulationInstallMitigationControllerDirectWriteProbeHooks\(\);",
        runtime,
    ) is not None,
    "direct-write hooks install exactly once": len(re.findall(r"^\s*InsulationInstallMitigationControllerDirectWriteProbeHooks\(\);", runtime, re.MULTILINE)) == 1,
    "die-temperature selector is exact": 'NSSelectorFromString(@"setDieTempControllerProperty:level:scaleToFixedPoint:")' in runtime,
    "service-property selector is exact": 'NSSelectorFromString(@"setServiceProperty:key:value:scaleToFixedPoint:")' in runtime,
    "die-temperature ABI is exact": '"v32@0:8^{__CFString=}16i24B28"' in runtime,
    "service-property ABI is exact": '"i36@0:8I16^{__CFString=}20i28B32"' in runtime,
    "private-method hooks are ABI-gated": "strcmp(actualEncoding, expectedEncoding) != 0" in runtime,
    "probe stores bounded direct-call state": 'state[@"directCalls"]' in probe and 'state[@"lastDirectCall"]' in probe,
    "direct-call ingress is coalesced": "InsulationProbeDirectCallDrainScheduled" in probe and "InsulationProbePendingDirectCalls" in probe,
    "direct-call ingress is lock-protected": "os_unfair_lock_lock(&InsulationProbeDirectCallLock)" in probe and "os_unfair_lock_unlock(&InsulationProbeDirectCallLock)" in probe,
    "probe marker accepts only downclock": 'strcmp(argv[i + 1], "downclock") != 0' in ctl_args,
    "probe marker uses dedicated notification": "com.be-huge.insulation.decisionProbe.mark.downclock" in ctl_main,
    "probe marker sender sets validation magic": "InsulationCtlProbeMarkMagic" in ctl_main and "notify_set_state(token, InsulationCtlProbeMarkMagic)" in ctl_main,
    "probe marker receiver consumes validation magic": "InsulationProbeConsumeMarkerMagic" in tweakinit and "notify_set_state(token, 0)" in tweakinit,
    "probe marker listener is compile-time gated": re.search(
        r"#if INSULATION_PROBE_ENABLED\s+CFNotificationCenterAddObserver\(center,\s+NULL,\s+InsulationProbeMarkerNotificationCallback",
        tweakinit,
    ) is not None,
    "probe marker captures ingress wall and monotonic time": marker_recorder is not None and all(token in marker_recorder.group("body") for token in [
        "NSTimeInterval markerTime = [[NSDate date] timeIntervalSince1970];",
        "double markerMonotonicSeconds = InsulationProbeMonotonicSeconds();",
        '@"time": @(markerTime)',
        '@"monotonicSeconds": @(markerMonotonicSeconds)',
    ]),
    "direct-call records include monotonic time": direct_call_recorder is not None and '@"monotonicSeconds": @(InsulationProbeMonotonicSeconds()),' in direct_call_recorder.group("body"),
    "probe marker snapshots setter state": '@"setters": [state[@"setters"] copy]' in probe,
    "probe marker freezes setter timeline": '@"setterTimeline": [state[@"setterTimeline"] copy]' in probe,
    "immediate marker flush suppresses stale delayed write": "InsulationProbeDirtyGeneration" in probe and "InsulationProbeWrittenGeneration" in probe,
    "setter timeline is bounded": "InsulationProbeSetterTimelineCapacity" in probe and 'InsulationProbeAppendBounded(state, @"setterTimeline"' in probe,
    "direct-call pending ingress is bounded": direct_call_recorder is not None and all(token in direct_call_recorder.group("body") for token in [
        "[InsulationProbePendingDirectCallRecords count] >= InsulationProbePendingDirectCallCapacity",
        "NSUInteger pruneCount = InsulationProbePendingDirectCallCapacity / 2",
        "removeObjectsInRange:NSMakeRange(0, pruneCount)",
        "InsulationProbePendingDirectCallDropped += pruneCount",
        "[InsulationProbePendingDirectCallRecords addObject:record]",
    ]) and "InsulationProbePendingDirectCallCapacity = 256" in probe,
    "direct-call pending drops are persisted": direct_call_drain is not None and all(token in direct_call_drain.group("body") for token in [
        "NSUInteger pendingDropped = InsulationProbePendingDirectCallDropped",
        "InsulationProbePendingDirectCallDropped = 0",
        'state[@"directCallIngressDropped"] = @([state[@"directCallIngressDropped"] unsignedIntegerValue] + pendingDropped)',
    ]),
    "direct-call timeline is bounded": "InsulationProbeDirectCallTimelineCapacity" in probe and 'InsulationProbeAppendBounded(state, @"directCallTimeline"' in probe,
    "probe marker freezes direct-call timeline": '@"directCallTimeline": [state[@"directCallTimeline"] copy]' in probe,
    "marker timeline is bounded": "InsulationProbeMarkerCapacity" in probe and 'InsulationProbeAppendBounded(state, @"markers"' in probe,
    "rejected thermal notify monitor is absent": "thermalpressurelevel" not in probe and "thermalstatus" not in probe,
    "production filter remains exactly thermalmonitord-only": re.fullmatch(
        r'\s*\{\s*Filter\s*=\s*\{\s*Executables\s*=\s*\(\s*"thermalmonitord"\s*\)\s*;\s*\}\s*;\s*\}\s*',
        filter_plist,
    ) is not None,
    "global IOKit probe sources are absent": not (root / "Sources/insulationObjC/InsulationIOKitProbe.m").exists() and not (root / "Sources/insulationObjC/InsulationMachIOProbe.m").exists(),
    "known global IOKit and Mach IO probe entrypoints are absent": not any(token in objc_probe_surface for token in [
        "InsulationProbeIOKitInstall",
        "InsulationProbeIOKitSnapshot",
        "InsulationMachIOProbeInstall",
        "InsulationMachIOProbeSnapshot",
        "IOConnectCallMethod",
        "IOConnectCallScalarMethod",
        "IOConnectCallAsyncMethod",
        "IORegistryEntrySetCFProperty",
        "IORegistryEntrySetCFProperties",
        "IOServiceOpen",
    ]),
    "probe does not add Substrate linkage": "CydiaSubstrate" not in makefile,
}
for label, condition in checks.items():
    if not condition:
        errors.append(label)

wrappers = {
    "die-temperature": (
        r"static void Insulation_MitigationController_setDieTempControllerProperty\([^\{]+\) \{(?P<body>.*?)\n\}",
        "Orig_MitigationController_setDieTempControllerProperty(self, _cmd, property, level, scaleToFixedPoint);",
        None,
    ),
    "service-property": (
        r"static int Insulation_MitigationController_setServiceProperty\([^\{]+\) \{(?P<body>.*?)\n\}",
        "Orig_MitigationController_setServiceProperty(self, _cmd, service, key, value, scaleToFixedPoint)",
        "return result;",
    ),
}
for label, (pattern, original_call, required_return) in wrappers.items():
    match = re.search(pattern, runtime, re.DOTALL)
    if match is None:
        errors.append(f"{label} wrapper is missing")
        continue
    body = match.group("body")
    if original_call not in body:
        errors.append(f"{label} does not call the original implementation with unchanged arguments")
    record_position = body.find("InsulationProbeRecordDirectCall")
    original_position = body.find(original_call)
    snapshot_position = body.find("InsulationProbeCopyCFString")
    if record_position < 0 or original_position < 0 or record_position < original_position:
        errors.append(f"{label} records before the original call")
    if snapshot_position >= 0 and snapshot_position < original_position:
        errors.append(f"{label} snapshots arguments before the original call")
    if required_return and required_return not in body:
        errors.append(f"{label} does not return the original result")

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    sys.exit(1)
print("OK: direct-write probe is pass-through, bounded, and compile-gated")
PY
if [[ $? -ne 0 ]]; then
  fail=1
fi

if [[ "$fail" == "1" ]]; then
  echo "One or more checks failed." >&2
  exit 1
fi

echo "All checks passed."
