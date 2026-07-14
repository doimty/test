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
prerm="layout/DEBIAN/prerm"
power_helper="Sources/insulationObjC/InsulationPowerHelper.m"

check_file "$header"
check_file "$source"
check_file "$prerm"

check_contains "$header" "insulationResetAllNativeThermalState" "shared reset-all API declared"
check_contains "$source" "insulationResetAllNativeThermalState" "shared reset-all API implemented"
check_contains "$source" "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration" "standalone CLI loads SystemConfiguration before dlsym"

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
  check_contains "$source" "CFSTR(\"$key\")" "native reset covers $key"
done

check_contains "$prerm" "--reset-native-state" "pre-removal script invokes shared reset"
check_contains "$prerm" "killall thermalmonitord" "pre-removal script restarts thermalmonitord"
check_contains "$power_helper" "insulationResetThermalMitigations();" "off/low removes mitigation override keys"
check_absent "$power_helper" "else if (InsulationLastThermalMitigationsDisabled)" "mitigation cleanup no longer depends on process-local Last"
check_absent "$power_helper" "insulationSetOSNotifNative()" "disabled notification override deletes keys"
check_absent "$power_helper" "insulationSetHIPNative()" "disabled HIP override deletes keys"
check_contains "$prerm" 'remove|deconfigure)' "pre-removal cleanup is scoped to removal"
check_contains "$prerm" 'upgrade)' "package upgrade explicitly skips native cleanup"

prerm_test_dir="$(mktemp -d)"
trap 'rm -rf "$prerm_test_dir"' EXIT
mkdir -p "$prerm_test_dir/bin"
cat >"$prerm_test_dir/bin/insulationctl" <<'EOF'
#!/bin/bash
printf 'reset %s\n' "$*" >>"$INSULATION_PRERM_TEST_LOG"
[[ "${INSULATION_RESET_FAIL:-0}" != "1" ]]
EOF
cat >"$prerm_test_dir/bin/killall" <<'EOF'
#!/bin/bash
printf 'kill %s\n' "$*" >>"$INSULATION_PRERM_TEST_LOG"
EOF
chmod +x "$prerm_test_dir/bin/insulationctl" "$prerm_test_dir/bin/killall"

: >"$prerm_test_dir/events"
PATH="$prerm_test_dir/bin:$PATH" INSULATION_PRERM_TEST_LOG="$prerm_test_dir/events" "$prerm" upgrade
if [[ ! -s "$prerm_test_dir/events" ]]; then
  echo "OK: package upgrade neither resets state nor restarts daemon"
else
  echo "FAIL: package upgrade performed removal cleanup" >&2
  fail=1
fi

: >"$prerm_test_dir/events"
PATH="$prerm_test_dir/bin:$PATH" INSULATION_PRERM_TEST_LOG="$prerm_test_dir/events" "$prerm" remove
if grep -Fxq 'reset --reset-native-state' "$prerm_test_dir/events" && grep -Fxq 'kill thermalmonitord' "$prerm_test_dir/events"; then
  echo "OK: package removal resets state before daemon restart"
else
  echo "FAIL: package removal did not reset state and restart daemon" >&2
  fail=1
fi

: >"$prerm_test_dir/events"
if PATH="$prerm_test_dir/bin:$PATH" INSULATION_PRERM_TEST_LOG="$prerm_test_dir/events" INSULATION_RESET_FAIL=1 "$prerm" remove 2>"$prerm_test_dir/stderr" &&
   grep -Fq 'native thermal-state cleanup failed' "$prerm_test_dir/stderr" &&
   grep -Fxq 'kill thermalmonitord' "$prerm_test_dir/events"; then
  echo "OK: cleanup failure is visible but does not block removal"
else
  echo "FAIL: cleanup failure contract is broken" >&2
  fail=1
fi

if [[ "$fail" != "0" ]]; then
  exit 1
fi

echo "All clean3 native-state contracts passed."
