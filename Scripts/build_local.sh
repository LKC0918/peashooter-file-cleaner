#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_DIR="$PROJECT_DIR/Build/DerivedData"

if ! xcode-select -p >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode and its Command Line Tools are required to build the Finder Sync app." >&2
  echo "Install Xcode, open it once, then select /Applications/Xcode.app/Contents/Developer." >&2
  exit 1
fi

xcodebuild \
  -project "$PROJECT_DIR/PeashooterFileCleaner.xcodeproj" \
  -scheme "Peashooter File Cleaner" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  clean build \
  "$@"

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/Peashooter File Cleaner.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build reported success, but the app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Built app: $APP_PATH"
