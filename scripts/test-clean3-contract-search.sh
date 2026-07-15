#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/insulation-contract-search.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/repo" "$TMP/bin"
cp -R \
  "$ROOT/Sources" \
  "$ROOT/InsulationCC" \
  "$ROOT/InsulationPrefs" \
  "$ROOT/scripts" \
  "$TMP/repo/"

for tool in bash grep head cut dirname; do
  resolved="$(command -v "$tool")"
  ln -s "$resolved" "$TMP/bin/$tool"
done

contract="$TMP/repo/scripts/test-clean3-mode-notification-contract.sh"
PATH="$TMP/bin" "$contract" >/dev/null

printf '\n// com.be-huge.insulation.runtimeState\n' >>"$TMP/repo/Sources/insulationObjC/TweakInit.m"
if PATH="$TMP/bin" "$contract" >"$TMP/forbidden.out" 2>"$TMP/forbidden.err"; then
  echo "FAIL: absence contract passed with a forbidden production string and no rg installed" >&2
  cat "$TMP/forbidden.out" >&2
  cat "$TMP/forbidden.err" >&2
  exit 1
fi

if grep -Fq 'legacy runtime-state notification retired' "$TMP/forbidden.err"; then
  echo "OK: absence contract detects forbidden strings without rg"
else
  echo "FAIL: absence contract failed for an unrelated reason" >&2
  cat "$TMP/forbidden.out" >&2
  cat "$TMP/forbidden.err" >&2
  exit 1
fi
