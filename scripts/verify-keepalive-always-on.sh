#!/bin/bash
# Static regression check for keepalive fix
# Verifies that the keepalive DisplayLink is always-on (no pause/evaluation)
# and that the fix matches proven 1.0.9 behavior.

set -euo pipefail
cd "$(dirname "$0")/.."
errors=0

check() {
    local desc="$1"
    local file="$2"
    local pattern="$3"
    local negate="${4:-}"
    echo -n "  [ ] $desc ... "
    if [ "$negate" = "negate" ]; then
        if grep -q "$pattern" "$file"; then
            echo "FAIL: found '$pattern' in $file"
            errors=$((errors+1))
        else
            echo "pass"
        fi
    else
        if grep -q "$pattern" "$file"; then
            echo "pass"
        else
            echo "FAIL: not found '$pattern' in $file"
            errors=$((errors+1))
        fi
    fi
}

echo "=== Keepalive always-on static regression check ==="
echo ""

# 1. No paused = YES in keepalive install
check "No paused in PMSBInstallKeepAliveLink" \
    "src/PMKeepAlive.xm.inc" \
    "paused[[:space:]]*=" negate

# 2. No PMSBKeepAliveEvaluate function
check "No PMSBKeepAliveEvaluate function" \
    "src/PMKeepAlive.xm.inc" \
    "PMSBKeepAliveEvaluate" negate

# 3. No eval timer
check "No eval timer" \
    "src/PMKeepAlive.xm.inc" \
    "PMSBKeepAliveEvalTimer" negate

# 4. No frontmost bundle ID query
check "No frontmost bundle ID query" \
    "src/PMKeepAlive.xm.inc" \
    "PMSBFrontmostBundleID" negate

# 5. No PSBIsAppHooked
check "No hooked check" \
    "src/PMKeepAlive.xm.inc" \
    "PMSBIsAppHooked" negate

# 6. No PMHookedTokenCache
check "No hooked token cache" \
    "src/PMKeepAlive.xm.inc" \
    "PMHookedTokenCache" negate

# 7. No PMSBKeepAliveNeeded
check "No keepalive-needed flag" \
    "src/PMKeepAlive.xm.inc" \
    "PMSBKeepAliveNeeded" negate

# 8. No PMSBKeepAliveHoldUntil
check "No hold-until hysteresis" \
    "src/PMKeepAlive.xm.inc" \
    "PMSBKeepAliveHoldUntil" negate

# 9. Link is created with range 120
check "Link has 120 range" \
    "src/PMKeepAlive.xm.inc" \
    "PMForce120Range"

# 10. Link is added to run loop
check "Link added to run loop" \
    "src/PMKeepAlive.xm.inc" \
    "addToRunLoop.*NSRunLoopCommonModes"

# 11. Comment says always-on
check "Comment says always-on" \
    "src/PMKeepAlive.xm.inc" \
    "Always-on"

# 12. No Darwin notify registration in PMBootstrap.xm.inc
check "No Darwin notify in PMBootstrap" \
    "src/PMBootstrap.xm.inc" \
    "com.doimty.pm120.hooked" negate

# 13. Version is bumped
check "Version bumped to 1.0.10+keepalive1" \
    "control" \
    "Version: 1.0.10+keepalive1"

echo ""
echo "=== Results: $errors errors ==="
exit $errors