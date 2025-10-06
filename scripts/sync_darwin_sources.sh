#!/usr/bin/env bash
set -euo pipefail

# Path to your shared Darwin implementation
COMMON_DIR="common/darwin/Classes"

# Flutter plugin target names (adjust if your plugin names differ)
IOS_TARGET="stream_webrtc_flutter"
MACOS_TARGET="stream_webrtc_flutter"

# Destination roots
IOS_DIR="ios/$IOS_TARGET/Sources/$IOS_TARGET"
MACOS_DIR="macos/$MACOS_TARGET/Sources/$MACOS_TARGET"

# Ensure destination dirs exist
mkdir -p "$IOS_DIR/include/$IOS_TARGET"
mkdir -p "$MACOS_DIR/include/$MACOS_TARGET"

echo "Syncing Darwin sources into iOS and macOS targets..."

# Copy implementation files (.m, .mm, .cpp, .c, .swift)
rsync -av --include='*/' \
  --include='*.m' --include='*.mm' \
  --include='*.cpp' --include='*.c' \
  --include='*.swift' \
  --exclude='*' \
  "$COMMON_DIR/" "$IOS_DIR/"

rsync -av --include='*/' \
  --include='*.m' --include='*.mm' \
  --include='*.cpp' --include='*.c' \
  --include='*.swift' \
  --exclude='*' \
  "$COMMON_DIR/" "$MACOS_DIR/"

# Copy public headers (.h, .hpp)
rsync -av --include='*/' \
  --include='*.h' --include='*.hpp' \
  --exclude='*' \
  "$COMMON_DIR/" "$IOS_DIR/include/$IOS_TARGET/"

rsync -av --include='*/' \
  --include='*.h' --include='*.hpp' \
  --exclude='*' \
  "$COMMON_DIR/" "$MACOS_DIR/include/$MACOS_TARGET/"

echo "✅ Sync complete!"