#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Peashooter File Cleaner.app"
BUILT_APP="$PROJECT_DIR/Build/DerivedData/Build/Products/Debug/$APP_NAME"
INSTALLED_APP="$HOME/Applications/$APP_NAME"
WORKFLOW_NAME="召唤豌豆射手.workflow"
SOURCE_WORKFLOW="$PROJECT_DIR/QuickAction/$WORKFLOW_NAME"
INSTALLED_WORKFLOW="$HOME/Library/Services/$WORKFLOW_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

"$SCRIPT_DIR/build_local.sh" "$@"

if [[ ! -d "$BUILT_APP" || ! -d "$SOURCE_WORKFLOW" ]]; then
  echo "The built app or Finder Quick Action is missing." >&2
  exit 1
fi

/usr/bin/killall "Peashooter File Cleaner" 2>/dev/null || true
/bin/mkdir -p "$HOME/Applications" "$HOME/Library/Services"
/usr/bin/ditto "$BUILT_APP" "$INSTALLED_APP"
/usr/bin/ditto "$SOURCE_WORKFLOW" "$INSTALLED_WORKFLOW"

"$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true
# xcodebuild registers every test/debug product with Launch Services. Multiple
# copies carrying the same Finder Sync bundle identifier can make Finder attach
# to a stale build. Unregister those parent apps without deleting their files;
# the installed bundle below remains the single canonical registration.
while IFS= read -r registered_parent; do
  if [[ -n "$registered_parent" && "$registered_parent" != "$INSTALLED_APP" ]]; then
    "$LSREGISTER" -u "$registered_parent" 2>/dev/null || true
  fi
done < <(
  /usr/bin/pluginkit -m -A -D -vv \
    -i com.peashooter.file-cleaner.finder-extension 2>/dev/null \
    | /usr/bin/sed -n 's/^[[:space:]]*Parent Bundle = //p'
)
"$LSREGISTER" -f -R -trusted "$INSTALLED_APP"
/usr/bin/pluginkit -a "$INSTALLED_APP/Contents/PlugIns/PeashooterFinderExtension.appex"
/usr/bin/pluginkit -e use -i com.peashooter.file-cleaner.finder-extension
/System/Library/CoreServices/pbs -update
/usr/bin/open "$INSTALLED_APP"
/usr/bin/killall Finder 2>/dev/null || true

echo "Installed app: $INSTALLED_APP"
echo "Installed Finder command: $INSTALLED_WORKFLOW"
echo "Right-click one regular file and choose: 召唤豌豆射手"
