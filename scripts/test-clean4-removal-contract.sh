#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

prerm="layout/DEBIAN/prerm"
postinst="layout/DEBIAN/postinst"
postrm="layout/DEBIAN/postrm"

for script in "$prerm" "$postinst" "$postrm"; do
  if [[ ! -x "$script" ]]; then
    echo "FAIL: missing executable maintainer script: $script" >&2
    exit 1
  fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/insulation-clean4-removal.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/insulationctl" <<'EOF'
#!/usr/bin/env bash
printf 'ctl %s\n' "$*" >>"$INSULATION_REMOVAL_TEST_LOG"
case "${1:-}" in
  --prepare-removal)
    [[ "${INSULATION_PREPARE_FAIL:-0}" != "1" ]]
    ;;
  --reset-native-state)
    [[ "${INSULATION_RESET_FAIL:-0}" != "1" ]]
    ;;
  --clear-removal-marker)
    [[ "${INSULATION_CLEAR_FAIL:-0}" != "1" ]]
    ;;
  *)
    exit 64
    ;;
esac
EOF
cat >"$TMP/bin/killall" <<'EOF'
#!/usr/bin/env bash
printf 'kill %s\n' "$*" >>"$INSULATION_REMOVAL_TEST_LOG"
[[ "${INSULATION_KILL_FAIL:-0}" != "1" ]]
EOF
chmod +x "$TMP/bin/insulationctl" "$TMP/bin/killall"

run_with_log() {
  local log="$1"
  shift
  : >"$log"
  PATH="$TMP/bin:$PATH" INSULATION_REMOVAL_TEST_LOG="$log" "$@"
}

assert_log() {
  local log="$1"
  shift
  local expected="$TMP/expected"
  : >"$expected"
  if [[ "$#" -gt 0 && "${1:-}" != "" ]]; then
    printf '%s\n' "$@" >"$expected"
  fi
  if ! cmp -s "$expected" "$log"; then
    echo "FAIL: unexpected lifecycle call order" >&2
    echo "expected:" >&2
    cat "$expected" >&2
    echo "actual:" >&2
    cat "$log" >&2
    exit 1
  fi
}

log="$TMP/events"
run_with_log "$log" "$prerm" upgrade
assert_log "$log" ""

run_with_log "$log" "$prerm" remove
assert_log "$log" \
  "ctl --prepare-removal" \
  "ctl --reset-native-state"

: >"$log"
if PATH="$TMP/bin:$PATH" INSULATION_REMOVAL_TEST_LOG="$log" INSULATION_PREPARE_FAIL=1 "$prerm" remove; then
  echo "FAIL: prepare failure did not block removal" >&2
  exit 1
fi
assert_log "$log" "ctl --prepare-removal"

: >"$log"
if PATH="$TMP/bin:$PATH" INSULATION_REMOVAL_TEST_LOG="$log" INSULATION_RESET_FAIL=1 "$prerm" remove; then
  echo "FAIL: cleanup failure did not block removal" >&2
  exit 1
fi
assert_log "$log" \
  "ctl --prepare-removal" \
  "ctl --reset-native-state"

run_with_log "$log" "$postinst" configure
assert_log "$log" \
  "ctl --clear-removal-marker" \
  "kill thermalmonitord"

: >"$log"
if PATH="$TMP/bin:$PATH" INSULATION_REMOVAL_TEST_LOG="$log" INSULATION_CLEAR_FAIL=1 "$postinst" configure; then
  echo "FAIL: marker-clear failure did not fail package configuration" >&2
  exit 1
fi
assert_log "$log" "ctl --clear-removal-marker"

run_with_log "$log" "$postrm" remove
assert_log "$log" "kill thermalmonitord"

run_with_log "$log" "$postrm" upgrade
assert_log "$log" ""

echo "All clean4 removal contracts passed."
