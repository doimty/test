#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/test-insulationctl-args.sh
scripts/test-insulation-cpu-state.sh
scripts/test-clean3-native-state-contract.sh
scripts/test-clean3-mode-notification-contract.sh

fail=0
expected_version="$(awk -F': ' 'tolower($1) == "version" { print $2; exit }' control)"
section() { printf '\n== %s ==\n' "$1"; }
check_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "OK: $label"
  else
    echo "FAIL: missing $label ($path)" >&2
    fail=1
  fi
}
check_symlink() {
  local label="$1" path="$2" target="$3"
  if [[ -L "$path" && "$(readlink "$path")" == "$target" ]]; then
    echo "OK: $label -> $target"
  else
    echo "FAIL: bad symlink $label ($path)" >&2
    [[ -e "$path" || -L "$path" ]] && ls -l "$path" >&2 || true
    fail=1
  fi
}

section "Source layout"
check_file "CLI parser header" Sources/insulationctl/InsulationCtlArgs.h
check_file "CLI parser source" Sources/insulationctl/InsulationCtlArgs.c
check_file "CLI main" Sources/insulationctl/main.m
check_file "native-state cleanup" Sources/insulationC/InsulationNativeState.m
check_file "CPU state model" Sources/insulationC/InsulationCPUState.c
check_file "pre-removal cleanup" layout/DEBIAN/prerm
check_symlink "short command layout" layout/usr/bin/ins insulationctl

if ! grep -q '^TOOL_NAME = insulationctl$' Makefile; then
  echo "FAIL: Makefile does not declare insulationctl tool" >&2
  fail=1
else
  echo "OK: Makefile declares insulationctl tool"
fi

if [[ -z "$expected_version" ]]; then
  echo "FAIL: could not read control version" >&2
  fail=1
else
  echo "OK: control version $expected_version"
fi

if grep -Eq '(<plist|touch .*insulation-prefs|cat >.*insulation-prefs|plutil .*thermalPowerMode)' layout/DEBIAN/postinst; then
  echo "FAIL: postinst appears to create or write prefs" >&2
  fail=1
else
  echo "OK: postinst does not create prefs"
fi

if [[ "$#" -gt 0 ]]; then
  section "Package contents"
fi

detect_otool() {
  if [[ -n "${OTOOL:-}" ]]; then
    printf '%s\n' "$OTOOL"
    return 0
  fi
  if command -v xcrun >/dev/null 2>&1 && xcrun -f otool >/dev/null 2>&1; then
    printf '%s\n' "xcrun otool"
    return 0
  fi
  if command -v otool >/dev/null 2>&1; then
    command -v otool
    return 0
  fi
  if [[ -n "${THEOS:-}" && -x "$THEOS/toolchain/linux/iphone/bin/otool" ]]; then
    printf '%s\n' "$THEOS/toolchain/linux/iphone/bin/otool"
    return 0
  fi
  if [[ -x "/root/.openclaw/workspace/toolchains/theos/toolchain/linux/iphone/bin/otool" ]]; then
    printf '%s\n' "/root/.openclaw/workspace/toolchains/theos/toolchain/linux/iphone/bin/otool"
    return 0
  fi
  return 1
}

for deb in "$@"; do
  if [[ ! -f "$deb" ]]; then
    echo "FAIL: package not found: $deb" >&2
    fail=1
    continue
  fi

  version="$(dpkg-deb -f "$deb" Version)"
  if [[ "$version" != "$expected_version" ]]; then
    echo "FAIL: $deb version is $version" >&2
    fail=1
  else
    echo "OK: $deb version $version"
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/root" "$tmp/control"
  dpkg-deb -x "$deb" "$tmp/root"
  dpkg-deb -e "$deb" "$tmp/control"

  ctl_path="$(find "$tmp/root" -path '*/usr/bin/insulationctl' -type f | head -n 1)"
  ins_path="$(find "$tmp/root" -path '*/usr/bin/ins' -type l | head -n 1)"
  postinst="$tmp/control/postinst"
  prerm="$tmp/control/prerm"

  if [[ -n "$ctl_path" ]]; then
    echo "OK: package contains ${ctl_path#$tmp/root}"
  else
    echo "FAIL: package missing usr/bin/insulationctl" >&2
    fail=1
  fi

  if [[ -n "$ins_path" && "$(readlink "$ins_path")" == "insulationctl" ]]; then
    echo "OK: package contains ${ins_path#$tmp/root} -> insulationctl"
  else
    echo "FAIL: package missing usr/bin/ins symlink" >&2
    fail=1
  fi

  if [[ -f "$postinst" ]] && ! grep -Eq '(<plist|touch .*insulation-prefs|cat >.*insulation-prefs|plutil .*thermalPowerMode)' "$postinst"; then
    echo "OK: package postinst does not create prefs"
  else
    echo "FAIL: package postinst missing or writes prefs" >&2
    fail=1
  fi

  if [[ -x "$prerm" ]] && grep -Fq -- '--reset-native-state' "$prerm"; then
    echo "OK: package prerm invokes native-state cleanup"
  else
    echo "FAIL: package prerm missing, non-executable, or does not invoke cleanup" >&2
    fail=1
  fi

  if grep -R -a -F -q -- 'com.be-huge.insulation.runtimeState' "$tmp/root" ||
     grep -R -a -F -q -- 'com.be-huge.insulation-restartThermalMonitor' "$tmp/root"; then
    echo "FAIL: package contains retired notification names" >&2
    fail=1
  else
    echo "OK: package contains no retired notification names"
  fi

  if grep -R -a -F -q -- 'com.be-huge.insulation-modeDidChange' "$tmp/root"; then
    echo "OK: package contains ordered mode-change notification"
  else
    echo "FAIL: package missing ordered mode-change notification" >&2
    fail=1
  fi

  if [[ -n "$ctl_path" ]]; then
    if otool_cmd="$(detect_otool)"; then
      libs="$tmp/insulationctl-libs.txt"
      # shellcheck disable=SC2086
      $otool_cmd -L "$ctl_path" > "$libs"
      if grep -q 'libroothide\.dylib' "$libs"; then
        echo "FAIL: insulationctl links libroothide.dylib" >&2
        cat "$libs" >&2
        fail=1
      else
        echo "OK: insulationctl has no libroothide.dylib dependency"
      fi
    else
      echo "FAIL: no otool available to inspect insulationctl dependencies" >&2
      fail=1
    fi
  fi

  rm -rf "$tmp"
  trap - RETURN
done

if [[ "$fail" == "1" ]]; then
  echo "insulationctl verification failed" >&2
  exit 1
fi

echo "insulationctl verification passed"
