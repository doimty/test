#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/InsulationCC/Sources/InsulationCCModule.m"
WORKFLOW="$ROOT/.github/workflows/build.yml"

python3 - "$SOURCE" "$WORKFLOW" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
workflow = pathlib.Path(sys.argv[2]).read_text()


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
):
    if forbidden in source:
        raise AssertionError(f"native checkmark path still contains custom dot code: {forbidden}")

if "self.useTrailingCheckmarkLayout = YES;" not in source:
    raise AssertionError("native checkmark is not configured for the trailing slot")
if 'if ([mode isEqualToString:@"lowPower"]) {\n        return [UIColor systemOrangeColor];\n    }' not in source:
    raise AssertionError("lowPower did not retain the previous system orange color")
if 'if ([mode isEqualToString:@"fullPower"]) {\n        return [UIColor systemRedColor];\n    }' not in source:
    raise AssertionError("fullPower did not retain the system red color")
if "return [UIColor whiteColor];" not in source:
    raise AssertionError("natural mode did not retain its white glyph color")

sync = method_body("- (void)syncMenuSelectionViews:")
if ".selected = selected;" not in sync:
    raise AssertionError("visible menu models are not synchronized for every row")
if "if (!selected)" not in sync or "itemView.trailingView = nil;" not in sync:
    raise AssertionError("stale native trailing checkmarks are not removed from unselected rows")

handle = method_body("- (void)_handleActionTapped:")
super_call = "[super _handleActionTapped:view];"
sync_call = "[self syncMenuSelectionViews:visibleMenuViews];"
refresh_call = "[self _updateLeadingAndTrailingViews];"
positions = [handle.rfind(call) for call in (super_call, sync_call, refresh_call)]
if min(positions) < 0 or positions != sorted(positions):
    raise AssertionError("expanded tap must finish as super -> model sync -> native accessory refresh")

if "visibleMenuStack.arrangedSubviews" not in handle:
    raise AssertionError("expanded tap does not capture current visible rows")

native_refresh = "[self _updateLeadingAndTrailingViews];"
native_refresh_guard = "if ([self respondsToSelector:@selector(_updateLeadingAndTrailingViews)]) {"
search_from = 0
while True:
    call = source.find(native_refresh, search_from)
    if call < 0:
        break
    if native_refresh_guard not in source[max(0, call - 160):call]:
        raise AssertionError("private native checkmark refresh is called without a selector guard")
    search_from = call + len(native_refresh)

sdk_commit = "0222fd5413cf4b9af096f37b4621afa2688572f7"
if f'git -C /tmp/theos-sdks fetch --depth 1 --filter=blob:none origin {sdk_commit}' not in workflow:
    raise AssertionError("CI does not shallow-fetch the pinned SDK commit directly")
if "git -C /tmp/theos-sdks checkout --detach FETCH_HEAD" not in workflow:
    raise AssertionError("CI does not detach at the explicitly fetched SDK commit")

print("OK: native checkmark selection and pinned SDK checkout are guarded and reproducible")
PY
