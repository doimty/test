#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

HOST_CC="${HOST_CC:-/usr/bin/clang}"
if [[ ! -x "$HOST_CC" ]]; then
  HOST_CC="$(command -v clang)"
fi

"$HOST_CC" -std=c11 -Wall -Wextra -Werror \
  -ISources/insulationctl \
  tests/insulationctl_args_test.c \
  Sources/insulationctl/InsulationCtlArgs.c \
  -o "$TMPDIR/insulationctl_args_test"

"$TMPDIR/insulationctl_args_test"
