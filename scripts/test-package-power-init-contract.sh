#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

path = Path("Sources/insulationC/ThermalManagerDimmingPatch.m")
text = path.read_text()
start = text.index("static id hook_PackagePowerCC_initWithParams")
end = text.index("/* ── MitigationController", start)
body = text[start:end]

guard = body.find("if (!orig_PackagePowerCC_initWithParams)")
patch = body.find("insulationThermalPatchAggressiveFullPowerEnabled()")
call = body.find("orig_PackagePowerCC_initWithParams)(self")

if guard < 0 or patch < 0 or call < 0:
    raise SystemExit("FAIL: PackagePowerCC init hook contract markers are missing")
if not guard < patch < call:
    raise SystemExit("FAIL: PackagePowerCC init hook must validate original IMP before patching params")

print("PackagePowerCC init hook validates original IMP before patching params.")
PY
