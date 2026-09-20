#!/bin/bash
# Static contract for the render-pacing ablation candidate.
# The candidate keeps the 120Hz request path but leaves Metal pacing to each app.
set -euo pipefail
cd "$(dirname "$0")/.."
errors=0

check_present() {
    local desc="$1" file="$2" pattern="$3"
    printf '  [ ] %s ... ' "$desc"
    if grep -Eq "$pattern" "$file"; then
        echo pass
    else
        echo "FAIL: not found '$pattern' in $file"
        errors=$((errors + 1))
    fi
}

check_absent() {
    local desc="$1" file="$2" pattern="$3"
    printf '  [ ] %s ... ' "$desc"
    if grep -Eq "$pattern" "$file"; then
        echo "FAIL: found '$pattern' in $file"
        errors=$((errors + 1))
    else
        echo pass
    fi
}

render="src/PMRenderingHooks.xm.inc"

check_present "CADisplayLink remains forced to 120" "$render" '%hook CADisplayLink'
check_present "CAAnimation remains forced to 120" "$render" '%hook CAAnimation'
check_absent "No CAMetalLayer drawable-count override" "$render" '%hook CAMetalLayer'
check_absent "No CAMetalDrawable minimum-duration override" "$render" '%hook CAMetalDrawable'
check_absent "No MTLCommandBuffer minimum-duration override" "$render" '%hook MTLCommandBuffer'
check_present "App persistent DynamicSource remains" "src/PMAppPersistent.xm.inc" 'PMAppEnsurePersistentSource'

printf '\n=== Results: %d errors ===\n' "$errors"
exit "$errors"
