#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_DIR="$ROOT_DIR/build/local/DerivedData"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/GhostNotch.app"

xcodebuild \
  -project "$ROOT_DIR/GhostNotch.xcodeproj" \
  -scheme GhostNotch \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

killall GhostNotch 2>/dev/null || true

while IFS='=' read -r key _; do
  case "$key" in
    NO_COLOR) unset "$key" ;;
    HERDR_CONFIG_PATH|HERDR_DISABLE_SOUND|HERDR_LOG|HERDR_SESSION) ;;
    HERDR_*) unset "$key" ;;
  esac
done < <(env)

open -n "$APP_PATH"
echo "Running $APP_PATH"
