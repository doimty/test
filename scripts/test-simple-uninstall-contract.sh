#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

prerm="layout/DEBIAN/prerm"
postrm="layout/DEBIAN/postrm"

if [[ -e "$prerm" ]]; then
  echo "FAIL: simple uninstall must not package a pre-removal transaction" >&2
  exit 1
fi
if [[ ! -x "$postrm" ]]; then
  echo "FAIL: missing executable postrm" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/insulation-simple-uninstall.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/killall" <<'EOF'
#!/usr/bin/env bash
printf 'kill %s\n' "$*" >>"$INSULATION_UNINSTALL_TEST_LOG"
[[ "${INSULATION_KILL_FAIL:-0}" != "1" ]]
EOF
chmod +x "$TMP/bin/killall"

run_postrm() {
  local action="$1"
  local fail_kill="${2:-0}"
  : >"$TMP/events"
  PATH="$TMP/bin:$PATH" \
    INSULATION_UNINSTALL_TEST_LOG="$TMP/events" \
    INSULATION_KILL_FAIL="$fail_kill" \
    "$postrm" "$action"
}

assert_events() {
  local expected="$1"
  if [[ "$(cat "$TMP/events")" != "$expected" ]]; then
    echo "FAIL: unexpected postrm events for current action" >&2
    printf 'expected: %s\nactual: %s\n' "$expected" "$(cat "$TMP/events")" >&2
    exit 1
  fi
}

run_postrm remove
assert_events "kill thermalmonitord"

run_postrm remove 1
assert_events "kill thermalmonitord"

run_postrm purge
assert_events "kill thermalmonitord"

run_postrm disappear
assert_events "kill thermalmonitord"

for action in upgrade failed-upgrade abort-install abort-upgrade; do
  run_postrm "$action"
  assert_events ""
done

: >"$TMP/events"
PATH="$TMP/bin:$PATH" \
  INSULATION_UNINSTALL_TEST_LOG="$TMP/events" \
  "$postrm"
assert_events ""

for file in \
  Sources/insulationctl/InsulationCtlArgs.h \
  Sources/insulationctl/InsulationCtlArgs.c \
  Sources/insulationctl/main.m \
  Sources/insulationC/include/InsulationNativeState.h \
  Sources/insulationC/InsulationNativeState.m; do
  if grep -Fq -- '--reset-native-state' "$file" ||
     grep -Fq -- 'INSULATION_CTL_ACTION_RESET_NATIVE' "$file" ||
     grep -Fq -- 'insulationResetAllNativeThermalState' "$file"; then
    echo "FAIL: uninstall-only native reset remains in $file" >&2
    exit 1
  fi
done

echo "All simple-uninstall contracts passed."
