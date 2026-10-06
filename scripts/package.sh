#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
./scripts/build.sh
BUILD_DIR="$PROJECT_DIR/dist.noindex"
STAGING="$BUILD_DIR/Package"
mkdir -p "$STAGING"
for PREVIOUS_APP in "$STAGING/OW120.app" "$STAGING/OverLaunch.app"; do
  if [[ -e "$PREVIOUS_APP" ]]; then rm -rf "$PREVIOUS_APP"; fi
done
cp -cR "$BUILD_DIR/OverLaunch.app" "$STAGING/OverLaunch.app"
ln -sfn /Applications "$STAGING/Applications"
cp RELEASE_NOTES.md "$STAGING/使用说明.md"
hdiutil create -volname OverLaunch -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/OverLaunch-0.4.4-arm64.dmg"
print "Packaged: $BUILD_DIR/OverLaunch-0.4.4-arm64.dmg"
