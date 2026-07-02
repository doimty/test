#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE="$(cd "$ROOT/../.." && pwd)"
TOOLCHAINS_DIR="${TOOLCHAINS_DIR:-$WORKSPACE/toolchains}"
THEOS_DIR="${THEOS:-$TOOLCHAINS_DIR/theos}"
BIN_DIR="$TOOLCHAINS_DIR/bin"

mkdir -p "$TOOLCHAINS_DIR" "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing command: $cmd" >&2
    return 1
  fi
}

missing=0
for cmd in git make dpkg-deb fakeroot curl tar xz rsync plistutil; do
  need_cmd "$cmd" || missing=1
done

if ! command -v clang >/dev/null 2>&1; then
  echo "missing command: clang (install clang/llvm before building)" >&2
  missing=1
fi

if ! command -v ldid >/dev/null 2>&1; then
  echo "missing command: ldid (install ldid before packaging)" >&2
  missing=1
fi

if [[ "$missing" == "1" ]]; then
  echo "Install the missing host tools first, then re-run this script." >&2
  exit 1
fi

install_theos() {
  local tmp_dir="$THEOS_DIR.tmp"
  local archive="${TMPDIR:-/tmp}/theos-main.tar.gz"
  local archive_dir="${TMPDIR:-/tmp}/theos-main"

  rm -rf "$tmp_dir" "$archive_dir"

  echo "Cloning Theos into $tmp_dir"
  if git -c http.version=HTTP/1.1 clone --recursive --depth 1 https://github.com/theos/theos.git "$tmp_dir" && [[ -d "$tmp_dir/makefiles" ]]; then
    return 0
  fi

  echo "Theos git clone failed; trying GitHub codeload archive fallback" >&2
  rm -rf "$tmp_dir" "$archive_dir"
  rm -f "$archive"
  mkdir -p "$archive_dir"

  curl --http1.1 -L --fail --retry 5 --retry-delay 5 --connect-timeout 20 --max-time 300 \
    -o "$archive" https://codeload.github.com/theos/theos/tar.gz/refs/heads/master
  tar -xzf "$archive" -C "$archive_dir" --strip-components=1
  if [[ ! -d "$archive_dir/makefiles" ]]; then
    echo "Theos archive fallback did not contain makefiles" >&2
    return 1
  fi
  mv "$archive_dir" "$tmp_dir"
}

if [[ ! -d "$THEOS_DIR/makefiles" ]]; then
  echo "Installing Theos into $THEOS_DIR"
  if install_theos; then
    rm -rf "$THEOS_DIR"
    mv "$THEOS_DIR.tmp" "$THEOS_DIR"
  else
    rm -rf "$THEOS_DIR.tmp"
    echo "Failed to install Theos into $THEOS_DIR" >&2
    exit 1
  fi
else
  echo "Theos already present: $THEOS_DIR"
fi

cat <<MSG

Environment setup status:
  export THEOS="$THEOS_DIR"
  export PATH="$BIN_DIR:\$THEOS/bin:\$PATH"

Next build probes:
  cd "$ROOT"
  scripts/check-objc-port.sh
  THEOS="$THEOS_DIR" make -n
  THEOS="$THEOS_DIR" scripts/build-objc-package.sh rootless

You still need a usable iPhoneOS SDK under Theos (usually in \$THEOS/sdks) before a real package build can link.
MSG
