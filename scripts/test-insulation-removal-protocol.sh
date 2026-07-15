#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_BIN="${CC:-clang}"
OUT="$(mktemp "${TMPDIR:-/tmp}/insulation-removal-protocol.XXXXXX")"
trap 'rm -f "$OUT"' EXIT

"$CC_BIN" \
  -std=c11 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$ROOT/Sources/insulationC" \
  "$ROOT/tests/insulation_removal_protocol_test.c" \
  "$ROOT/Sources/insulationC/InsulationRemovalProtocol.c" \
  -o "$OUT"

"$OUT"
