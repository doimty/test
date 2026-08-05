#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/InsulationCC/Sources/InsulationCCModule.m"

python3 - "$SOURCE" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()


def method_body(signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing method: {signature}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise AssertionError(f"unterminated method: {signature}")


for forbidden in (
    "InsulationModeDotView",
    "InsulationModeDotDiameter",
    ".leadingView =",
    ".trailingView =",
):
    if forbidden in source:
        raise AssertionError(f"native checkmark path still contains custom accessory code: {forbidden}")

if "self.useTrailingCheckmarkLayout = YES;" not in source:
    raise AssertionError("native checkmark is not configured for the trailing slot")

sync = method_body("- (void)syncMenuSelectionViews:")
if ".selected = selected;" not in sync:
    raise AssertionError("visible menu models are not synchronized for every row")

handle = method_body("- (void)_handleActionTapped:")
super_call = "[super _handleActionTapped:view];"
sync_call = "[self syncMenuSelectionViews:visibleMenuViews];"
refresh_call = "[self _updateLeadingAndTrailingViews];"
positions = [handle.rfind(call) for call in (super_call, sync_call, refresh_call)]
if min(positions) < 0 or positions != sorted(positions):
    raise AssertionError("expanded tap must finish as super -> model sync -> native accessory refresh")

if "visibleMenuStack.arrangedSubviews" not in handle:
    raise AssertionError("expanded tap does not capture current visible rows")

print("OK: native checkmark selection is synchronized and refreshed on the visible CC menu")
PY
