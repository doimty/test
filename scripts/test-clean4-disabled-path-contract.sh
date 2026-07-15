#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

require_literal() {
  local file="$1" literal="$2" label="$3"
  if ! grep -Fq -- "$literal" "$file"; then
    echo "FAIL: $label ($file)" >&2
    exit 1
  fi
}

require_function_literal() {
  local file="$1" function_signature="$2" literal="$3" label="$4"
  if ! awk -v signature="$function_signature" -v literal="$literal" '
    index($0, signature) { in_function = 1 }
    in_function && index($0, literal) { found = 1 }
    in_function && /^}/ { exit found ? 0 : 1 }
    END { if (!in_function || !found) exit 1 }
  ' "$file"; then
    echo "FAIL: $label ($file: $function_signature)" >&2
    exit 1
  fi
}

require_literal Sources/insulationObjC/TweakInit.m \
  'InsulationRemovalInitializeFromMarker()' \
  'ObjC constructor does not honor the removal marker'
require_literal Sources/insulationC/ThermalManagerDimmingPatch.m \
  'InsulationRemovalInitializeFromMarker()' \
  'dimming-patch constructor does not honor the removal marker'
require_literal Sources/insulationObjC/TweakInit.m \
  'InsulationRemovalCurrentMarkerIsValid()' \
  'removal callback does not reject spurious notifications without a valid marker'
require_literal Sources/insulationObjC/TweakInit.m \
  'InsulationPreparePuppetEventsForRemoval();' \
  'removal callback does not quiesce queued apply work'
require_literal Sources/insulationObjC/TweakInit.m \
  'InsulationRemovalAcknowledgeCurrentMarker(&error)' \
  'removal callback does not acknowledge its nonce and pid'
require_literal Sources/insulationObjC/InsulationPowerHelper.m \
  'InsulationApplyScheduleEventCancelSoon' \
  'removal preparation does not cancel Soon work'
require_literal Sources/insulationObjC/InsulationPowerHelper.m \
  'InsulationRemovalLatchDisabled();' \
  'removal preparation does not latch disabled state first'
require_literal Sources/insulationObjC/InsulationPowerHelper.m \
  'InsulationCPUPerformanceState = InsulationCPUStateInitial();' \
  'removal preparation does not reset CPU restore ownership'
require_literal Sources/insulationObjC/InsulationPowerHelper.m \
  'InsulationOwnedDarwinThermalPressure = NO;' \
  'removal preparation does not release Darwin-pressure ownership'
require_literal Sources/insulationObjC/InsulationDictHelper.m \
  'if (InsulationRemovalIsDisabled())' \
  'thermal plist patch has no removal pass-through gate'
require_literal Sources/insulationC/ThermalControl.m \
  'if (InsulationRemovalIsDisabled())' \
  'native SCPreferences/pressure writes have no removal gate'
require_literal Sources/insulationC/InsulationNativeState.m \
  'insulationVerifyThermalKeysAbsent' \
  'native cleanup does not verify all keys are absent'
require_literal Sources/insulationObjC/InsulationRemovalGuard.m \
  'InsulationRemovalParseAcknowledgment' \
  'helper does not validate acknowledgment nonce and pid'
require_literal Sources/insulationObjC/InsulationRemovalGuard.m \
  'InsulationRemovalWaitForPIDExit' \
  'helper does not confirm acknowledged pid exit'
require_literal Sources/insulationObjC/InsulationRemovalGuard.m \
  'O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600' \
  'marker and acknowledgment are not created as root-only files'
require_literal Sources/insulationObjC/InsulationRemovalGuard.m \
  'info.st_uid == 0 && (info.st_mode & 0077) == 0' \
  'marker and acknowledgment ownership/mode are not validated'
require_function_literal Sources/insulationC/ThermalManagerDimmingPatch.m \
  'static id hook_PackagePowerCC_initWithParams' \
  'InsulationRemovalIsDisabled()' \
  'PackagePowerCC configuration replacement lacks explicit removal pass-through'
require_function_literal Sources/insulationC/ThermalManagerDimmingPatch.m \
  'static int hook_MitigationController_getPackagePowerZoneMetric' \
  'InsulationRemovalIsDisabled()' \
  'package power-zone getter lacks removal pass-through'

marker_check_line="$(grep -n -F 'if (!InsulationRemovalCurrentMarkerIsValid())' Sources/insulationObjC/TweakInit.m | head -1 | cut -d: -f1)"
latch_line="$(grep -n -F 'InsulationPreparePuppetEventsForRemoval();' Sources/insulationObjC/TweakInit.m | head -1 | cut -d: -f1)"
if [[ -z "$marker_check_line" || -z "$latch_line" || "$marker_check_line" -ge "$latch_line" ]]; then
  echo "FAIL: removal callback latches disabled before validating the marker" >&2
  exit 1
fi

awk '
  /^static void Insulation_MitigationController_/ {
    in_hook = 1
    guarded = 0
    hook = $0
  }
  in_hook && /InsulationRemovalIsDisabled\(\)/ { guarded = 1 }
  in_hook && /^}/ {
    if (!guarded) {
      printf "FAIL: MitigationController hook lacks removal pass-through: %s\n", hook > "/dev/stderr"
      failed = 1
    }
    in_hook = 0
  }
  END { exit failed ? 1 : 0 }
' Sources/insulationObjC/InsulationRuntimeHooks.m

constructor_gate_count="$(grep -R -F -l -- 'InsulationRemovalInitializeFromMarker()' \
  Sources/insulationObjC/TweakInit.m \
  Sources/insulationC/ThermalManagerDimmingPatch.m | wc -l | tr -d ' ')"
if [[ "$constructor_gate_count" != "2" ]]; then
  echo "FAIL: expected removal gates in both constructors" >&2
  exit 1
fi

if grep -R -F -q -- '/var/run/' \
  Sources/insulationC/InsulationRemovalProtocol.h \
  Sources/insulationObjC/InsulationRemovalGuard.m; then
  echo "FAIL: removal transaction state must not live under /var/run" >&2
  exit 1
fi

if grep -R -E -q -- 'SIGSTOP|launchctl[[:space:]]+(bootout|bootstrap)' \
  Sources/insulationObjC Sources/insulationC layout/DEBIAN; then
  echo "FAIL: removal lifecycle uses a rejected process-control strategy" >&2
  exit 1
fi

echo "All clean4 disabled-path contracts passed."
