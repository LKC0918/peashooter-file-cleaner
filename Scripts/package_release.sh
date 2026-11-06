#!/bin/bash
set -euo pipefail

if [[ "$#" != 2 || "$1" != "--unsigned-beta" || "$2" != "--authorized-assets" ]]; then
  echo "Usage: $0 --unsigned-beta --authorized-assets" >&2
  echo "This produces an unnotarized beta only. Confirm redistribution rights before packaging." >&2
  exit 64
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$PROJECT_DIR/Distribution/version.txt")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
  echo "Expected an explicit beta version." >&2
  exit 1
fi
OUTPUT_DIR="$PROJECT_DIR/dist/$VERSION"
if [[ -e "$OUTPUT_DIR" ]]; then
  echo "Output already exists; preserve it and choose a new beta version or move it aside." >&2
  exit 1
fi
"$SCRIPT_DIR/verify_project.sh"
ruby "$SCRIPT_DIR/check_public_snapshot.rb"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/peashooter-release.XXXXXX")"
mkdir -p "$OUTPUT_DIR" "$WORK_DIR/disk"

# Disable debug metadata and normalize Swift source paths in both CPU slices.
# Build logs and intermediate files stay outside the payload and are never uploaded.
if ! xcodebuild \
  -project "$PROJECT_DIR/PeashooterFileCleaner.xcodeproj" \
  -scheme "Peashooter File Cleaner" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$WORK_DIR/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  DEBUG_INFORMATION_FORMAT= SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
  "OTHER_SWIFT_FLAGS=\$(inherited) -no-serialize-debugging-options -file-prefix-map \"$PROJECT_DIR=/Source/PeashooterFileCleaner\" -debug-prefix-map \"$PROJECT_DIR=/Source/PeashooterFileCleaner\" -file-prefix-map \"$WORK_DIR=/Build/PeashooterFileCleaner\" -debug-prefix-map \"$WORK_DIR=/Build/PeashooterFileCleaner\"" \
  SWIFT_EMIT_LOC_STRINGS=NO ENABLE_TESTABILITY=NO \
  build > "$WORK_DIR/build.log" 2>&1; then
  echo "Release build failed. Review the local build log (not part of the package): $WORK_DIR/build.log" >&2
  exit 1
fi
APP="$WORK_DIR/disk/Peashooter File Cleaner.app"
ditto --norsrc --noextattr --noqtn "$WORK_DIR/DerivedData/Build/Products/Release/Peashooter File Cleaner.app" "$APP"
EXTENSION="$APP/Contents/PlugIns/PeashooterFinderExtension.appex"
/usr/bin/strip -S "$APP/Contents/MacOS/Peashooter File Cleaner"
/usr/bin/strip -S "$EXTENSION/Contents/MacOS/PeashooterFinderExtension"
/usr/bin/codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$PROJECT_DIR/FinderExtension/PeashooterFinderExtension.entitlements" "$EXTENSION"
/usr/bin/codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$PROJECT_DIR/Resources/PeashooterFileCleaner.entitlements" "$APP"
ruby "$SCRIPT_DIR/verify_release.rb" "$APP"

ln -s /Applications "$WORK_DIR/disk/Applications"
ditto --norsrc --noextattr "$PROJECT_DIR/Resources/UserGuide.html" "$WORK_DIR/disk/使用说明.html"
ditto --norsrc --noextattr "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$WORK_DIR/disk/第三方资源说明.txt"
DMG="$OUTPUT_DIR/Peashooter-File-Cleaner-$VERSION-universal.dmg"
/usr/bin/hdiutil create -quiet -volname "Peashooter File Cleaner" -srcfolder "$WORK_DIR/disk" \
  -fs HFS+ -format UDZO "$DMG"
/usr/bin/hdiutil verify "$DMG"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
echo "Built unnotarized beta: $DMG"
echo "Staged verified application: $APP"
echo "No Developer ID identity, certificate, build log or debug symbols are included."
