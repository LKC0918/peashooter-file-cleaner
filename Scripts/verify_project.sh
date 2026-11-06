#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/PeashooterFileCleaner.xcodeproj/project.pbxproj"
SOURCE_ONLY=false
if [[ "${1:-}" == "--source-only" && "$#" == 1 ]]; then
  SOURCE_ONLY=true
elif [[ "$#" != 0 ]]; then
  echo "Usage: $0 [--source-only]" >&2
  exit 64
fi

required_files=(
  "$PROJECT_FILE"
  "$PROJECT_DIR/Resources/AppInfo.plist"
  "$PROJECT_DIR/FinderExtension/Info.plist"
  "$PROJECT_DIR/Core/TrashService.swift"
  "$PROJECT_DIR/FinderExtension/FinderSync.swift"
  "$PROJECT_DIR/QuickAction/召唤豌豆射手.workflow/Contents/Info.plist"
  "$PROJECT_DIR/QuickAction/召唤豌豆射手.workflow/Contents/Resources/document.wflow"
)

if [[ "$SOURCE_ONLY" == false ]]; then
  required_files+=(
    "$PROJECT_DIR/Resources/AppIcon.icns"
    "$PROJECT_DIR/Resources/assets/projectile/projectile_01.png"
    "$PROJECT_DIR/Resources/assets/sounds/firepea.wav"
    "$PROJECT_DIR/Resources/assets/sounds/splat.wav"
    "$PROJECT_DIR/Resources/assets/sounds/pop.wav"
  )
fi

for required in "${required_files[@]}"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing required project file: $required" >&2
    exit 1
  fi
done

plutil -lint \
  "$PROJECT_FILE" \
  "$PROJECT_DIR/Resources/AppInfo.plist" \
  "$PROJECT_DIR/Resources/PeashooterFileCleaner.entitlements" \
  "$PROJECT_DIR/FinderExtension/Info.plist" \
  "$PROJECT_DIR/FinderExtension/PeashooterFinderExtension.entitlements" \
  "$PROJECT_DIR/QuickAction/召唤豌豆射手.workflow/Contents/Info.plist" \
  "$PROJECT_DIR/QuickAction/召唤豌豆射手.workflow/Contents/Resources/document.wflow" >/dev/null

xmllint --noout "$PROJECT_DIR/PeashooterFileCleaner.xcodeproj/xcshareddata/xcschemes/Peashooter File Cleaner.xcscheme"
bash -n "$PROJECT_DIR/Scripts/build_local.sh"
bash -n "$PROJECT_DIR/Scripts/install_local.sh"
bash -n "$PROJECT_DIR/Scripts/verify_project.sh"
bash -n "$PROJECT_DIR/Scripts/package_release.sh"

expected_idle=12
expected_shoot=11
expected_impact=4
expected_zombies=16

if [[ "$SOURCE_ONLY" == false ]]; then
  [[ "$(find "$PROJECT_DIR/Resources/assets/peashooter/idle" -name 'idle_*.png' | wc -l | tr -d ' ')" == "$expected_idle" ]]
  [[ "$(find "$PROJECT_DIR/Resources/assets/peashooter/shoot" -name 'shoot_*.png' | wc -l | tr -d ' ')" == "$expected_shoot" ]]
  [[ "$(find "$PROJECT_DIR/Resources/assets/impact" -name 'impact_*.png' | wc -l | tr -d ' ')" == "$expected_impact" ]]
  [[ "$(find "$PROJECT_DIR/Resources/assets/zombies/walk" -name 'zombie_*.png' | wc -l | tr -d ' ')" == "$expected_zombies" ]]
fi

if grep -R -n -E 'removeItem|unlink\(' \
  "$PROJECT_DIR/App" \
  "$PROJECT_DIR/Animation" \
  "$PROJECT_DIR/Core" \
  "$PROJECT_DIR/FinderExtension"; then
  echo "A permanent-delete API was found in production Swift sources." >&2
  exit 1
fi

if [[ "$(grep -R -h 'trashItem' "$PROJECT_DIR/Core"/*.swift | wc -l | tr -d ' ')" != "1" ]]; then
  echo "Expected exactly one production trashItem call." >&2
  exit 1
fi

ruby - "$PROJECT_FILE" <<'RUBY'
source = File.read(ARGV[0])
definitions = source.scan(/^\s*([A-F0-9]{24})(?:\s+\/\*.*?\*\/)?\s*=\s*\{/).flatten.uniq
references = source.scan(/\b[A-F0-9]{24}\b/).flatten.uniq
missing = references - definitions
abort("Unresolved Xcode object IDs: #{missing.join(', ')}") unless missing.empty?
RUBY

if xcode-select -p >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  xcodebuild -list -project "$PROJECT_DIR/PeashooterFileCleaner.xcodeproj" >/dev/null
  echo "Xcode project structure: verified by xcodebuild"
else
  echo "Xcode project structure: static checks passed; xcodebuild skipped (Xcode/CLT unavailable)"
fi

if [[ "$SOURCE_ONLY" == true ]]; then
  echo "Asset inventory: skipped (public source-only edition)"
else
  echo "Asset inventory: verified"
fi
echo "Plists, entitlements, scheme and pbxproj: verified"
echo "Production permanent-delete API scan: passed"
