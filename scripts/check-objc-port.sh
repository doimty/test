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
main_c_files=$(find Sources/insulationC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) | sort)
prefs_objc_files=$(find InsulationPrefs/Sources/InsulationPrefsObjC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) | sort)
prefs_c_files=$(find InsulationPrefs/Sources/InsulationPrefsC -type f \( -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp' \) | sort)
check_nonzero "main ObjC files" "$(printf '%s\n' "$main_objc_files" | sed '/^$/d' | wc -l | tr -d ' ')"
check_nonzero "main C support files" "$(printf '%s\n' "$main_c_files" | sed '/^$/d' | wc -l | tr -d ' ')"
check_nonzero "prefs ObjC files" "$(printf '%s\n' "$prefs_objc_files" | sed '/^$/d' | wc -l | tr -d ' ')"
check_nonzero "prefs C support files" "$(printf '%s\n' "$prefs_c_files" | sed '/^$/d' | wc -l | tr -d ' ')"

section "No Swift/Orion references in active sources"
objc_refs=$(grep -RInE 'Orion|orion_init|ClassHook|import Swift|IPowerHepler|IDictHepler|IFileManager' Sources/insulationObjC InsulationPrefs/Sources/InsulationPrefsObjC Sources/insulationC || true)
if [[ -z "$objc_refs" ]]; then
  echo "OK: no Swift/Orion references in active sources"
else
  echo "$objc_refs" >&2
  fail=1
fi

section "No legacy Orion entrypoints"
if [[ -e Sources/insulationC/Tweak.m ]]; then
  echo "FAIL: legacy Orion tweak entry file still exists" >&2
  fail=1
else
  echo "OK: no legacy Orion tweak entry file"
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

if [[ "$fail" == "1" ]]; then
  echo "One or more checks failed." >&2
  exit 1
fi

echo "All checks passed."
