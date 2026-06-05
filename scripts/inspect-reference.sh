#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
pkg="references/com.promotion120_1.0.0-17+debug_iphoneos-arm64.deb"
dpkg-deb -I "$pkg" control
printf '\n--- contents ---\n'
dpkg-deb -c "$pkg"
printf '\n--- sha256 ---\n'
sha256sum "$pkg"
