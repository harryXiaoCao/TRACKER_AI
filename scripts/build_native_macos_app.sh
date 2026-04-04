#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/macos/TrackerAI/TrackerAI.xcodeproj"
SCHEME="TrackerAI"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/TrackerAI-derived-data}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/.build/TrackerAI.xcarchive}"
DESTINATION="${DESTINATION:-platform=macOS}"
BUILD_ACTION="${BUILD_ACTION:-build}"
RUN_TESTS="${RUN_TESTS:-0}"
VALIDATE_RELEASE="${VALIDATE_RELEASE:-1}"
SOURCE_ONLY_VALIDATION=0

usage() {
  cat <<'EOF'
Usage: bash scripts/build_native_macos_app.sh [options]

Options:
  --build                    Build the app bundle (default).
  --archive                  Create an Xcode archive.
  --configuration NAME       Override the Xcode build configuration.
  --derived-data-path PATH   Override the derived data path.
  --archive-path PATH        Override the archive output path.
  --run-tests                Run `swift test` before building.
  --skip-tests               Skip `swift test`.
  --skip-validation          Skip release validation checks.
  --source-only-validation   Validate release configuration without building.
  --help                     Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_ACTION="build"
      shift
      ;;
    --archive)
      BUILD_ACTION="archive"
      shift
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    --archive-path)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --run-tests)
      RUN_TESTS=1
      shift
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --skip-validation)
      VALIDATE_RELEASE=0
      shift
      ;;
    --source-only-validation)
      SOURCE_ONLY_VALIDATION=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$VALIDATE_RELEASE" -eq 1 ]]; then
  echo "Validating native macOS release configuration..."
  bash "$ROOT_DIR/scripts/validate_native_macos_release.sh" \
    --project-root "$ROOT_DIR" \
    --source-only
fi

if [[ "$SOURCE_ONLY_VALIDATION" -eq 1 ]]; then
  echo "Source-only validation complete."
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required to build the native TrackerAI macOS app." >&2
  exit 1
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  echo "Running Swift test suite before the native build..."
  swift test
fi

APP_BUNDLE_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/TrackerAI.app"

if [[ "$BUILD_ACTION" == "archive" ]]; then
  echo "Archiving native TrackerAI macOS app..."
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -archivePath "$ARCHIVE_PATH" \
    archive
  APP_BUNDLE_PATH="$ARCHIVE_PATH/Products/Applications/TrackerAI.app"
else
  echo "Building native TrackerAI macOS app..."
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  APP_BUNDLE_PATH="$(find "${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}" -maxdepth 1 -type d -name '*.app' | head -n 1)"
fi

if [[ "$VALIDATE_RELEASE" -eq 1 ]]; then
  echo "Validating built native app bundle..."
  bash "$ROOT_DIR/scripts/validate_native_macos_release.sh" \
    --project-root "$ROOT_DIR" \
    --app "$APP_BUNDLE_PATH"
fi

echo "Build complete."
if [[ "$BUILD_ACTION" == "archive" ]]; then
  echo "Archive:"
  echo "  $ARCHIVE_PATH"
else
  echo "Derived data:"
  echo "  $DERIVED_DATA_PATH"
fi
echo "App bundle:"
echo "  $APP_BUNDLE_PATH"
