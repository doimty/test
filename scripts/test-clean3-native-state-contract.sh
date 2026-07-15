#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
check_file() {
  if [[ -f "$1" ]]; then
    echo "OK: $1"
  else
    echo "FAIL: missing $1" >&2
    fail=1
  fi
}
check_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if [[ -f "$file" ]] && grep -Fq -- "$needle" "$file"; then
    echo "OK: $label"
  else
    echo "FAIL: $label" >&2
    fail=1
  fi
}
check_absent() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if [[ -f "$file" ]] && ! grep -Fq -- "$needle" "$file"; then
    echo "OK: $label"
  else
    echo "FAIL: $label" >&2
    fail=1
  fi
}

header="Sources/insulationC/include/InsulationNativeState.h"
source="Sources/insulationC/InsulationNativeState.m"
power_helper="Sources/insulationObjC/InsulationPowerHelper.m"
cli_header="Sources/insulationctl/InsulationCtlArgs.h"
cli_source="Sources/insulationctl/InsulationCtlArgs.c"
cli_main="Sources/insulationctl/main.m"

check_file "$header"
check_file "$source"
check_contains "$source" "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration" "installed native-state helper loads SystemConfiguration before dlsym"

for key in \
  engageBehavior \
  engageBehaviorPersistentlyEnabled \
  OSThermalNotificationEnabled \
  OSThermalNotificationPersistentlyEnabled \
  hipOverride \
  hipPersistentlyEnabled \
  simulateHip \
  sunlightOverride \
  sunlightOverridePersistentlyEnabled; do
  check_contains "$source" "CFSTR(\"$key\")" "installed mode cleanup covers $key"
done

check_contains "$power_helper" "insulationResetThermalMitigations();" "off/low removes mitigation override keys while installed"
check_absent "$power_helper" "else if (InsulationLastThermalMitigationsDisabled)" "mitigation cleanup no longer depends on process-local Last"
check_absent "$power_helper" "insulationSetOSNotifNative()" "disabled notification override deletes keys while installed"
check_absent "$power_helper" "insulationSetHIPNative()" "disabled HIP override deletes keys while installed"

for file in "$header" "$source" "$cli_header" "$cli_source" "$cli_main"; do
  check_absent "$file" "insulationResetAllNativeThermalState" "reset-all API absent from $file"
  check_absent "$file" "INSULATION_CTL_ACTION_RESET_NATIVE" "reset-all CLI action absent from $file"
  check_absent "$file" "--reset-native-state" "reset-all CLI spelling absent from $file"
done

if [[ -e layout/DEBIAN/prerm ]]; then
  echo "FAIL: uninstall must not package native-state cleanup" >&2
  fail=1
else
  echo "OK: uninstall has no pre-removal native-state cleanup"
fi

if [[ "$fail" != "0" ]]; then
  exit 1
fi

echo "All installed native-state contracts passed."
