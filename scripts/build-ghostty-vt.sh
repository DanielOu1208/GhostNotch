#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor/ghostty-vt"
BUILD_DIR="$VENDOR_DIR/_build"

GHOSTTY_VERSION="${GHOSTTY_VERSION:-tip}"
ZIG_VERSION="${ZIG_VERSION:-0.15.2}"

case "$(uname -m)" in
  arm64) ZIG_ARCH="aarch64" ;;
  x86_64) ZIG_ARCH="x86_64" ;;
  *)
    echo "Unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

ZIG_TARGET="${ZIG_TARGET:-${ZIG_ARCH}-macos.14.0}"
ZIG_NAME="zig-${ZIG_ARCH}-macos-${ZIG_VERSION}"
ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_NAME}.tar.xz"
if [[ "$GHOSTTY_VERSION" == "tip" ]]; then
  GHOSTTY_ARCHIVE_NAME="ghostty-tip-source"
  GHOSTTY_URL="https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz"
else
  GHOSTTY_ARCHIVE_NAME="ghostty-${GHOSTTY_VERSION}"
  GHOSTTY_URL="https://release.files.ghostty.org/${GHOSTTY_VERSION}/${GHOSTTY_ARCHIVE_NAME}.tar.gz"
fi

mkdir -p "$BUILD_DIR" "$VENDOR_DIR/include"

download() {
  local url="$1"
  local output="$2"

  if [[ -f "$output" ]]; then
    echo "Using cached $(basename "$output")"
    return
  fi

  echo "Downloading $url"
  curl --fail --location --output "$output" "$url"
}

if [[ -n "${GHOSTTY_ZIG:-}" ]]; then
  ZIG_EXE="$GHOSTTY_ZIG"
  ZIG_PROVIDER="custom"
elif command -v brew >/dev/null 2>&1 && [[ -x "$(brew --prefix zig@0.15 2>/dev/null)/bin/zig" ]]; then
  ZIG_EXE="$(brew --prefix zig@0.15)/bin/zig"
  ZIG_PROVIDER="brew"
else
  download "$ZIG_URL" "$BUILD_DIR/${ZIG_NAME}.tar.xz"

  if [[ ! -x "$BUILD_DIR/$ZIG_NAME/zig" ]]; then
    echo "Extracting $ZIG_NAME"
    rm -rf "$BUILD_DIR/$ZIG_NAME"
    tar -xJf "$BUILD_DIR/${ZIG_NAME}.tar.xz" -C "$BUILD_DIR"
  fi

  ZIG_EXE="$BUILD_DIR/$ZIG_NAME/zig"
  ZIG_PROVIDER="downloaded"
fi

download "$GHOSTTY_URL" "$BUILD_DIR/${GHOSTTY_ARCHIVE_NAME}.tar.gz"

SOURCE_MARKER="$BUILD_DIR/.${GHOSTTY_ARCHIVE_NAME}.source-path"
if [[ ! -f "$SOURCE_MARKER" || ! -d "$(cat "$SOURCE_MARKER")" ]]; then
  echo "Extracting $GHOSTTY_ARCHIVE_NAME"
  rm -rf "$BUILD_DIR/${GHOSTTY_ARCHIVE_NAME}-extract"
  mkdir -p "$BUILD_DIR/${GHOSTTY_ARCHIVE_NAME}-extract"
  tar -xzf "$BUILD_DIR/${GHOSTTY_ARCHIVE_NAME}.tar.gz" -C "$BUILD_DIR/${GHOSTTY_ARCHIVE_NAME}-extract"
  find "$BUILD_DIR/${GHOSTTY_ARCHIVE_NAME}-extract" -maxdepth 1 -mindepth 1 -type d | head -n 1 > "$SOURCE_MARKER"
fi

GHOSTTY_SOURCE_DIR="$(cat "$SOURCE_MARKER")"
GHOSTTY_SOURCE_VERSION="$(basename "$GHOSTTY_SOURCE_DIR")"

echo "Building libghostty-vt ${GHOSTTY_VERSION}"
(
  cd "$GHOSTTY_SOURCE_DIR"
  if "$ZIG_EXE" build -h 2>/dev/null | grep -q -- '-Demit-lib-vt'; then
    "$ZIG_EXE" build \
      -Dtarget="$ZIG_TARGET" \
      -Demit-lib-vt=true \
      -Demit-xcframework=true \
      -Doptimize=ReleaseFast
  else
    "$ZIG_EXE" build lib-vt \
    -Dtarget="$ZIG_TARGET" \
    -Doptimize=ReleaseFast
  fi
)

XCFRAMEWORK_PATH="$(find "$GHOSTTY_SOURCE_DIR/zig-out" -name '*ghostty*vt*.xcframework' -type d | head -n 1)"
LIB_PATH="$(find "$GHOSTTY_SOURCE_DIR/zig-out" -name 'libghostty-vt*.dylib' -type f | head -n 1)"

if [[ -n "$XCFRAMEWORK_PATH" ]]; then
  echo "Installing $(basename "$XCFRAMEWORK_PATH")"
  rm -rf "$VENDOR_DIR/GhosttyVT.xcframework"
  cp -R "$XCFRAMEWORK_PATH" "$VENDOR_DIR/GhosttyVT.xcframework"
  ARTIFACT="GhosttyVT.xcframework"
elif [[ -n "$LIB_PATH" ]]; then
  echo "Installing $(basename "$LIB_PATH")"
  mkdir -p "$VENDOR_DIR/lib"
  rm -f "$VENDOR_DIR"/lib/libghostty-vt*.dylib
  cp "$LIB_PATH" "$VENDOR_DIR/lib/"
  ARTIFACT="lib/$(basename "$LIB_PATH")"
else
  echo "Ghostty build completed, but no libghostty-vt artifact was found under zig-out." >&2
  find "$GHOSTTY_SOURCE_DIR/zig-out" -maxdepth 5 -print >&2
  exit 1
fi

echo "Installing public headers"
rm -rf "$VENDOR_DIR/include/ghostty"
cp -R "$GHOSTTY_SOURCE_DIR/zig-out/include/ghostty" "$VENDOR_DIR/include/ghostty"

cat > "$VENDOR_DIR/VERSION" <<VERSION
ghostty=${GHOSTTY_VERSION}
ghostty_source=${GHOSTTY_SOURCE_VERSION}
zig=${ZIG_VERSION}
zig_provider=${ZIG_PROVIDER}
source=${GHOSTTY_URL}
artifact=${ARTIFACT}
VERSION

echo "Installed libghostty-vt into $VENDOR_DIR"
