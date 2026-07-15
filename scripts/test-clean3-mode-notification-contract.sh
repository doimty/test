#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
check_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "$needle" "$file"; then
    echo "OK: $label"
  else
    echo "FAIL: $label" >&2
    fail=1
  fi
}
check_absent_tree() {
  local needle="$1"
  local label="$2"
  local matches=""
  local status=0
  shift 2
  if matches="$(grep -RFn -- "$needle" "$@" 2>&1)"; then
    echo "FAIL: $label" >&2
    printf '%s\n' "$matches" >&2
    fail=1
    return
  else
    status=$?
  fi
  if [[ "$status" == "1" ]]; then
    echo "OK: $label"
  else
    echo "FAIL: $label (search failed with status $status)" >&2
    printf '%s\n' "$matches" >&2
    fail=1
  fi
}

mode_name="com.be-huge.insulation-modeDidChange"
tweak_init="Sources/insulationObjC/TweakInit.m"
power_helper="Sources/insulationObjC/InsulationPowerHelper.m"
cpu_state_header="Sources/insulationC/include/InsulationCPUState.h"
cpu_state_source="Sources/insulationC/InsulationCPUState.c"
cli="Sources/insulationctl/main.m"
cc="InsulationCC/Sources/InsulationCCModule.m"
prefs_params="InsulationPrefs/Sources/InsulationPrefsObjC/InsulationPrefsParams.m"
prefs_helper="InsulationPrefs/Sources/InsulationPrefsObjC/InsulationPrefsNotificationHelper.m"
prefs_controller="InsulationPrefs/Sources/InsulationPrefsObjC/RootListController.m"
root_plist="InsulationPrefs/Resources/Root.plist"
production=(Sources InsulationCC InsulationPrefs)

for file in "$tweak_init" "$cli" "$cc" "$prefs_params"; do
  check_contains "$file" "$mode_name" "single mode notification wired in $file"
done
check_contains "$tweak_init" "InsulationModeChangeNotificationCallback" "daemon has dedicated ordered mode callback"
check_contains "$tweak_init" "InsulationExecutePuppetEventWithSource(@\"notification.modeDidChange\")" "mode callback performs synchronous apply"
check_contains "$tweak_init" "kill(getpid(), SIGTERM)" "mode callback restarts daemon after apply"

apply_line=$(grep -n 'InsulationExecutePuppetEventWithSource(@"notification.modeDidChange")' "$tweak_init" | head -1 | cut -d: -f1 || true)
kill_line=$(grep -n 'kill(getpid(), SIGTERM)' "$tweak_init" | head -1 | cut -d: -f1 || true)
if [[ -n "$apply_line" && -n "$kill_line" && "$apply_line" -lt "$kill_line" ]]; then
  echo "OK: mode apply precedes daemon restart"
else
  echo "FAIL: mode apply must precede daemon restart" >&2
  fail=1
fi

check_absent_tree "com.be-huge.insulation.runtimeState" "legacy runtime-state notification retired" "${production[@]}"
check_absent_tree "com.be-huge.insulation-restartThermalMonitor" "independent restart notification retired" "${production[@]}"
check_contains "$prefs_helper" "InsulationPrefsPostModeChangeNotification" "prefs exposes mode-only notification helper"
check_contains "$prefs_controller" "InsulationPrefsPostModeChangeNotification();" "power-mode writes use mode notification"
check_contains "$prefs_controller" "InsulationPrefsPostApplyNotifications();" "independent toggles retain apply notification"
check_absent_tree "<key>PostNotification</key>" "specifier does not emit a duplicate mode notification" "$root_plist"

check_contains "$cpu_state_header" "InsulationCPUPhaseBoot" "CPU state model names boot phase"
check_contains "$cpu_state_header" "InsulationCPUPhaseSteady" "CPU state model names steady phase"
check_contains "$cpu_state_header" "InsulationCPUPhaseLeaving" "CPU state model names leaving phase"
check_contains "$cpu_state_header" "appliedMode" "CPU state tracks applied mode separately"
check_contains "$power_helper" "InsulationCPUStateStep" "production CPU apply path uses tested state model"
check_absent_tree "InsulationLastCPUPerformanceMode" "boot guard no longer writes a fake last mode" "$power_helper"
check_contains "$cpu_state_source" "state->pendingRestoreCount = restoreEventCount" "fresh off or leaving mode arms restore passes"
check_contains "$power_helper" "dispatch_async(queue" "Soon generation checks run on apply queue"

if [[ "$fail" != "0" ]]; then
  exit 1
fi

echo "All clean3 mode-notification contracts passed."
