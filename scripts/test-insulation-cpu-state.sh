#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_BIN="${CC:-clang}"
OUT="$(mktemp "${TMPDIR:-/tmp}/insulation-cpu-state.XXXXXX")"
trap 'rm -f "$OUT"' EXIT

"$CC_BIN" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$ROOT/Sources/insulationC/include" \
  "$ROOT/tests/insulation_cpu_state_test.c" \
  "$ROOT/Sources/insulationC/InsulationCPUState.c" \
  -o "$OUT"

"$OUT"
