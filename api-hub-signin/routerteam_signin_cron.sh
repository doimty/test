#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ENV_FILE="${API_HUB_SIGNIN_ENV:-$BASE_DIR/api_hub_signin.env}"
SCRIPT="${API_HUB_SIGNIN_SCRIPT:-$BASE_DIR/api_hub_signin.py}"
CONFIG="${API_HUB_SIGNIN_CONFIG:-$BASE_DIR/api_hub_signin.json}"
LOG_DIR="${API_HUB_SIGNIN_LOG_DIR:-$BASE_DIR/logs}"
LOG_FILE="${API_HUB_SIGNIN_LOG_FILE:-$LOG_DIR/api_hub_signin.log}"

mkdir -p "$LOG_DIR"

set -a
source "$ENV_FILE"
set +a

status=0
{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') api hub signin start ====="
  "$SCRIPT" --config "$CONFIG" || status=$?
  echo "===== $(date '+%Y-%m-%d %H:%M:%S %z') api hub signin end status=$status ====="
} >> "$LOG_FILE" 2>&1

exit "$status"
