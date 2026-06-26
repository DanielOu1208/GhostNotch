#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-$ROOT_DIR/GhostNotch.xcodeproj}"
SCHEME="${SCHEME:-GhostNotch}"
CONFIGURATION="${CONFIGURATION:-Release}"
VERSION="${VERSION:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-GhostNotch Self-Signed Release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_DIR="$DIST_DIR/build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
DMG_ROOT="$BUILD_DIR/dmg-root"
APP_NAME="GhostNotch.app"
APP_PATH="$DIST_DIR/$APP_NAME"
DMG_NAME="GhostNotch-v$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
VOLUME_NAME="GhostNotch v$VERSION"

usage() {
  cat <<EOF
Usage: scripts/package-dmg.sh

Environment overrides:
  VERSION=0.1.0
  SIGN_IDENTITY="GhostNotch Self-Signed Release"
  DIST_DIR="$ROOT_DIR/dist"

The signing identity must exist in your macOS keychain. For v0, create a local
self-signed code-signing certificate named:

  GhostNotch Self-Signed Release
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "error: hdiutil is required." >&2
  exit 1
fi

mkdir -p "$DIST_DIR" "$BUILD_DIR"
rm -rf "$DERIVED_DATA_DIR" "$DMG_ROOT" "$APP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: built app not found at $BUILT_APP" >&2
  exit 1
fi

echo "Staging app..."
ditto "$BUILT_APP" "$APP_PATH"

echo "Signing app with identity: $SIGN_IDENTITY"
if ! codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp=none \
  --sign "$SIGN_IDENTITY" \
  "$APP_PATH"; then
  cat >&2 <<EOF

error: app signing failed.

Create a local self-signed code-signing certificate in Keychain Access named:

  $SIGN_IDENTITY

Or rerun with SIGN_IDENTITY set to the exact certificate name.
EOF
  exit 1
fi

echo "Creating DMG..."
mkdir -p "$DMG_ROOT"
ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Signing DMG with identity: $SIGN_IDENTITY"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$DMG_PATH"

echo "Writing checksum..."
(
  cd "$DIST_DIR"
  shasum -a 256 "$DMG_NAME" > "$(basename "$CHECKSUM_PATH")"
)

echo
echo "Created:"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
