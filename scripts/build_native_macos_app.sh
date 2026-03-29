#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/macos/TrackerAI/TrackerAI.xcodeproj"
SCHEME="TrackerAI"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/TrackerAI-derived-data}"

cd "$ROOT_DIR"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required to build the native TrackerAI macOS app." >&2
  exit 1
fi

echo "Building native TrackerAI macOS app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

echo "Build complete."
echo "Derived data:"
echo "  $DERIVED_DATA_PATH"
