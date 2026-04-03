#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

if ! command -v conda >/dev/null 2>&1; then
  echo "conda is required to build Tracker AI" >&2
  exit 1
fi

echo "Building Tracker AI macOS release candidate..."
echo "This is the legacy Python/PyInstaller packaging path kept for compatibility work."
conda run -n tracker-ai python -m pip install -e .[release]
conda run -n tracker-ai pyinstaller --clean --noconfirm packaging/TrackerAI.spec

echo "Build complete:"
echo "  $ROOT_DIR/dist/TrackerAI.app"
