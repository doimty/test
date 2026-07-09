#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/test-insulationctl-args.sh

fail=0
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
check_symlink "short command layout" layout/usr/bin/ins insulationctl

if ! grep -q '^TOOL_NAME = insulationctl$' Makefile; then
  echo "FAIL: Makefile does not declare insulationctl tool" >&2
  fail=1
else
  echo "OK: Makefile declares insulationctl tool"
fi

if ! grep -q '^Version: 0\.1\.36\.40-cli1$' control; then
  echo "FAIL: control version is not 0.1.36.40-cli1" >&2
  fail=1
else
  echo "OK: control version 0.1.36.40-cli1"
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

for deb in "$@"; do
  if [[ ! -f "$deb" ]]; then
    echo "FAIL: package not found: $deb" >&2
    fail=1
    continue
  fi

  version="$(dpkg-deb -f "$deb" Version)"
  if [[ "$version" != "0.1.36.40-cli1" ]]; then
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

  rm -rf "$tmp"
  trap - RETURN
done

if [[ "$fail" == "1" ]]; then
  echo "insulationctl verification failed" >&2
  exit 1
fi

echo "insulationctl verification passed"
