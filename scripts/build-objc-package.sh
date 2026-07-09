#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/../.." && pwd)"
TOOLCHAINS_DIR="${TOOLCHAINS_DIR:-$WORKSPACE/toolchains}"
export PATH="$TOOLCHAINS_DIR/bin:$PATH"
cd "$ROOT"

SCHEME="${THEOS_PACKAGE_SCHEME:-${1:-rootless}}"
SDKVERSION="${SDKVERSION:-16.5}"

missing_tool=0
required_tools=(make clang dpkg-deb ldid rsync plistutil)
if [[ "$(uname -s)" != "Darwin" ]]; then
  required_tools+=(fakeroot)
fi
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing command: $tool" >&2
    missing_tool=1
  fi
done
if [[ "$missing_tool" == "1" ]]; then
  echo "Install missing host tools before packaging." >&2
  exit 1
fi

if [[ -z "${THEOS:-}" ]]; then
  echo "THEOS is not set. Install Theos and export THEOS=/path/to/theos before building." >&2
  exit 1
fi

if [[ ! -d "$THEOS/makefiles" ]]; then
  echo "THEOS does not look valid: $THEOS/makefiles is missing" >&2
  exit 1
fi

scripts/check-objc-port.sh
scripts/test-insulationctl-args.sh

info_backup="$(mktemp)"
loader_backup="$(mktemp)"
cp InsulationPrefs/Resources/Info.plist "$info_backup"
cp InsulationPrefs/layout/Library/PreferenceLoader/Preferences/InsulationPrefs.plist "$loader_backup"
restore_files() {
  cp "$info_backup" InsulationPrefs/Resources/Info.plist
  cp "$loader_backup" InsulationPrefs/layout/Library/PreferenceLoader/Preferences/InsulationPrefs.plist
  rm -f "$info_backup" "$loader_backup"
}
trap restore_files EXIT

cp scripts/objc-packaging/Info.plist InsulationPrefs/Resources/Info.plist
cp scripts/objc-packaging/InsulationPrefs.plist InsulationPrefs/layout/Library/PreferenceLoader/Preferences/InsulationPrefs.plist

export THEOS_PACKAGE_SCHEME="$SCHEME"
export FINALPACKAGE=1

make clean SDKVERSION="$SDKVERSION" THEOS_PACKAGE_SCHEME="$SCHEME"
make package FINALPACKAGE=1 SDKVERSION="$SDKVERSION" THEOS_PACKAGE_SCHEME="$SCHEME"
