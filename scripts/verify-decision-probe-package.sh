#!/usr/bin/env bash
set -euo pipefail

DEB="${1:-}"
PROBE_ENABLED="${2:-${INSULATION_PROBE_ENABLED:-0}}"

if [[ -z "$DEB" || ! -f "$DEB" ]]; then
  echo "usage: $0 <package.deb> [0|1]" >&2
  exit 2
fi
if [[ "$PROBE_ENABLED" != "0" && "$PROBE_ENABLED" != "1" ]]; then
  echo "probe state must be 0 or 1: $PROBE_ENABLED" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/insulation-decision-probe.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

dpkg-deb -x "$DEB" "$TMP_DIR/package"
TWEAK="$(find "$TMP_DIR/package" -type f -name 'insulation.dylib' -print -quit)"
FILTER="$(find "$TMP_DIR/package" -type f -path '*/Library/MobileSubstrate/DynamicLibraries/insulation.plist' -print -quit)"
if [[ -z "$TWEAK" || -z "$FILTER" ]]; then
  echo "package is missing insulation.dylib or insulation.plist" >&2
  exit 1
fi

strings -a "$TWEAK" > "$TMP_DIR/tweak.strings"
plistutil -i "$FILTER" -o "$TMP_DIR/filter.xml"

required_markers=(
  'setDieTempControllerProperty:level:scaleToFixedPoint:'
  'setServiceProperty:key:value:scaleToFixedPoint:'
  'com.be-huge.insulation.decisionProbe.mark.downclock'
  'directCallTimeline'
  'decision-iokit-correlation-1'
  'com.be-huge.insulation-decision-probe.plist'
)

for marker in "${required_markers[@]}"; do
  if [[ "$PROBE_ENABLED" == "1" ]]; then
    grep -F "$marker" "$TMP_DIR/tweak.strings" >/dev/null || {
      echo "probe tweak is missing marker: $marker" >&2
      exit 1
    }
  elif grep -F "$marker" "$TMP_DIR/tweak.strings" >/dev/null; then
    echo "default tweak contains probe marker: $marker" >&2
    exit 1
  fi
done

for forbidden in \
  'InsulationProbeIOKitInstall' \
  'InsulationProbeIOKitSnapshot' \
  'InsulationMachIOProbeInstall' \
  'InsulationMachIOProbeSnapshot' \
  'IOConnectCallMethod' \
  'IOConnectCallScalarMethod' \
  'IOConnectCallAsyncMethod' \
  'IOConnectCallAsyncScalarMethod' \
  'IOConnectCallAsyncStructMethod' \
  'IOConnectCallStructMethod' \
  'IORegistryEntrySetCFProperty' \
  'IORegistryEntrySetCFProperties' \
  'IOServiceOpen'; do
  if grep -F "$forbidden" "$TMP_DIR/tweak.strings" >/dev/null; then
    echo "tweak contains rejected global IOKit/Mach marker: $forbidden" >&2
    exit 1
  fi
done

python3 - "$TMP_DIR/filter.xml" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    data = plistlib.load(stream)
executables = data.get("Filter", {}).get("Executables")
if executables != ["thermalmonitord"]:
    raise SystemExit(f"substrate filter must target only thermalmonitord: {executables!r}")
PY

printf 'OK: decision probe package state=%s, bounded markers verified, exact thermalmonitord-only filter\n' "$PROBE_ENABLED"
