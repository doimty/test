#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <package.deb> <probe-enabled:0|1>" >&2
  exit 2
fi

DEB="$1"
PROBE_ENABLED="$2"
[[ -f "$DEB" ]] || { echo "missing package: $DEB" >&2; exit 1; }
[[ "$PROBE_ENABLED" == "0" || "$PROBE_ENABLED" == "1" ]] || { echo "probe state must be 0 or 1" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
dpkg-deb -x "$DEB" "$TMP/root"
dpkg-deb -e "$DEB" "$TMP/control"

PACKAGE="$(dpkg-deb -f "$DEB" Package)"
VERSION="$(dpkg-deb -f "$DEB" Version)"
ARCH="$(dpkg-deb -f "$DEB" Architecture)"
[[ "$PACKAGE" == "com.doimty.promotion" ]] || { echo "unexpected package: $PACKAGE" >&2; exit 1; }
[[ "$ARCH" == "iphoneos-arm64e" ]] || { echo "unexpected architecture: $ARCH" >&2; exit 1; }

DYLIB="$(find "$TMP/root" -path '*/Library/MobileSubstrate/DynamicLibraries/ProMotion120.dylib' -type f -print -quit)"
FILTER="$(find "$TMP/root" -path '*/Library/MobileSubstrate/DynamicLibraries/ProMotion120.plist' -type f -print -quit)"
[[ -n "$DYLIB" && -n "$FILTER" ]] || { echo "missing tweak dylib/filter" >&2; exit 1; }
# Verify roothide scheme: dylib must depend on a .jbroot loader path
OTOOL="${OTOOL:-otool}"
if ! "$OTOOL" -L "$DYLIB" 2>/dev/null | grep -qF 'jbroot'; then
  echo "not a roothide build (no jbroot dependency: $OTOOL -L $DYLIB)" >&2
  exit 1
fi

STRINGS="$TMP/strings.txt"
strings "$DYLIB" > "$STRINGS"
for retired in 'PMTelegramProbe' 'PMTGProbe' 'tgprobe' 'tgprobe.rejected' 'rejectedBundleID'; do
  if grep -Fqi "$retired" "$STRINGS"; then
    echo "retired Telegram probe string present: $retired" >&2
    exit 1
  fi
done

probe_markers=(
  '1.0.9+fgprobe1'
  'com.doimty.promotion120.probe.mark.drop'
  'com.promotion120.foreground-probe.'
  'foregroundEnd'
)
if [[ "$PROBE_ENABLED" == "1" ]]; then
  for marker in "${probe_markers[@]}"; do
    grep -Fq "$marker" "$STRINGS" || { echo "missing probe marker: $marker" >&2; exit 1; }
  done
else
  for marker in "${probe_markers[@]}"; do
    if grep -Fq "$marker" "$STRINGS"; then
      echo "clean package contains probe marker: $marker" >&2
      exit 1
    fi
  done
fi

python3 - "$FILTER" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    root = plistlib.load(handle)
actual = root.get("Filter", {}).get("Bundles")
expected = [
    "com.apple.UIKit",
    "com.apple.springboard",
    "com.apple.UserNotificationsUIServer",
    "com.apple.springboard.SpringBoardOutofCallUI",
]
if actual != expected:
    raise SystemExit(f"unexpected injection filter: {actual!r}")
print("OK: exact production injection filter")
PY

printf 'OK: package=%s version=%s architecture=%s probe=%s\n' "$PACKAGE" "$VERSION" "$ARCH" "$PROBE_ENABLED"
