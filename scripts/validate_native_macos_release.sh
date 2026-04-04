#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE_PATH=""
SOURCE_ONLY=0

usage() {
  cat <<'EOF'
Usage: bash scripts/validate_native_macos_release.sh [options]

Options:
  --project-root PATH   Override the repository root.
  --app PATH            Validate a built .app bundle in addition to source config.
  --source-only         Only validate source-side release configuration.
  --help                Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      ROOT_DIR="$2"
      shift 2
      ;;
    --app)
      APP_BUNDLE_PATH="$2"
      shift 2
      ;;
    --source-only)
      SOURCE_ONLY=1
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

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "Missing required directory: $path" >&2
    exit 1
  fi
}

expect_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(/usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
  if [[ "$value" != "$expected" ]]; then
    echo "Unexpected plist value for $key in $plist: expected '$expected', found '${value:-<missing>}'" >&2
    exit 1
  fi
}

expect_plist_nonempty() {
  local plist="$1"
  local key="$2"
  local value
  value="$(/usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    echo "Missing plist value for $key in $plist" >&2
    exit 1
  fi
  if [[ "$value" == *'$('* ]]; then
    echo "Unresolved build setting for $key in $plist: $value" >&2
    exit 1
  fi
}

expect_plist_boolean_true() {
  local plist="$1"
  local key="$2"
  local json
  json="$(/usr/bin/plutil -convert json -o - "$plist" 2>/dev/null || true)"
  if ! /usr/bin/grep -Eq "\"$key\"[[:space:]]*:[[:space:]]*(true|1)" <<<"$json"; then
    echo "Expected boolean true for $key in $plist" >&2
    exit 1
  fi
}

expect_json_pattern() {
  local file="$1"
  local pattern="$2"
  if ! /usr/bin/grep -Eq "$pattern" "$file"; then
    echo "Expected pattern not found in $file: $pattern" >&2
    exit 1
  fi
}

validate_source_configuration() {
  local info_plist="$ROOT_DIR/macos/TrackerAI/Resources/Info.plist"
  local entitlements="$ROOT_DIR/macos/TrackerAI/Resources/TrackerAI.entitlements"
  local icon_catalog="$ROOT_DIR/macos/TrackerAI/Resources/Assets.xcassets/AppIcon.appiconset"
  local icon_manifest="$icon_catalog/Contents.json"
  local release_config="$ROOT_DIR/macos/TrackerAI/Config/Release.xcconfig"
  local base_config="$ROOT_DIR/macos/TrackerAI/Config/Base.xcconfig"

  require_file "$info_plist"
  require_file "$entitlements"
  require_dir "$icon_catalog"
  require_file "$icon_manifest"
  require_file "$release_config"
  require_file "$base_config"

  expect_plist_value "$info_plist" "CFBundlePackageType" "APPL"
  expect_plist_value "$info_plist" "LSApplicationCategoryType" "public.app-category.education"

  expect_plist_boolean_true "$entitlements" "com.apple.security.app-sandbox"
  expect_plist_boolean_true "$entitlements" "com.apple.security.files.user-selected.read-write"

  expect_json_pattern "$icon_manifest" '"idiom"[[:space:]]*:[[:space:]]*"mac"'

  local icon_files=(
    "icon_16x16.png"
    "icon_16x16@2x.png"
    "icon_32x32.png"
    "icon_32x32@2x.png"
    "icon_128x128.png"
    "icon_128x128@2x.png"
    "icon_256x256.png"
    "icon_256x256@2x.png"
    "icon_512x512.png"
    "icon_512x512@2x.png"
  )

  local icon_file
  for icon_file in "${icon_files[@]}"; do
    require_file "$icon_catalog/$icon_file"
  done

  expect_json_pattern "$base_config" '^PRODUCT_BUNDLE_IDENTIFIER = .+'
  expect_json_pattern "$base_config" '^MARKETING_VERSION = .+'
  expect_json_pattern "$base_config" '^CURRENT_PROJECT_VERSION = .+'
  expect_json_pattern "$base_config" '^CODE_SIGN_ENTITLEMENTS = Resources/TrackerAI\.entitlements$'
  expect_json_pattern "$base_config" '^INFOPLIST_FILE = Resources/Info\.plist$'
  expect_json_pattern "$base_config" '^ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon$'

  expect_json_pattern "$release_config" '^VALIDATE_PRODUCT = YES$'

  echo "Source release configuration looks valid."
}

validate_built_bundle() {
  local app_bundle="$1"
  local info_plist="$app_bundle/Contents/Info.plist"
  local executable
  local entitlements_dump

  require_dir "$app_bundle"
  require_file "$info_plist"

  expect_plist_nonempty "$info_plist" "CFBundleIdentifier"
  expect_plist_nonempty "$info_plist" "CFBundleExecutable"
  expect_plist_nonempty "$info_plist" "CFBundleName"
  expect_plist_nonempty "$info_plist" "CFBundleShortVersionString"
  expect_plist_nonempty "$info_plist" "CFBundleVersion"
  expect_plist_nonempty "$info_plist" "LSMinimumSystemVersion"
  expect_plist_value "$info_plist" "CFBundlePackageType" "APPL"
  expect_plist_value "$info_plist" "LSApplicationCategoryType" "public.app-category.education"

  executable="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$info_plist")"
  require_file "$app_bundle/Contents/MacOS/$executable"
  require_file "$app_bundle/Contents/Resources/AppIcon.icns"

  entitlements_dump="$(mktemp "/tmp/trackerai-release-entitlements.XXXXXX.plist")"
  if /usr/bin/codesign -d --entitlements :- "$app_bundle" >"$entitlements_dump" 2>/dev/null; then
    expect_plist_boolean_true "$entitlements_dump" "com.apple.security.app-sandbox"
    expect_plist_boolean_true "$entitlements_dump" "com.apple.security.files.user-selected.read-write"
  else
    echo "Warning: built app is not signed; skipping embedded entitlement verification." >&2
  fi
  rm -f "$entitlements_dump"

  echo "Built app bundle looks valid: $app_bundle"
}

validate_source_configuration

if [[ "$SOURCE_ONLY" -eq 1 ]]; then
  exit 0
fi

if [[ -z "$APP_BUNDLE_PATH" ]]; then
  echo "No app bundle supplied; source validation completed." >&2
  exit 0
fi

validate_built_bundle "$APP_BUNDLE_PATH"
