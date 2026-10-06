#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
if [[ $# == 0 ]]; then
  ./scripts/build.sh
elif [[ $# != 1 || "$1" != '--no-build' ]]; then
  print -u2 'Usage: package.sh [--no-build]'; exit 1
fi
BUILD_DIR="$PROJECT_DIR/dist.noindex"
RELEASE_VERSION="$(python3 -c 'import json; print(json.load(open("release.json"))["artifactVersion"])')"
codesign --verify --deep --strict "$BUILD_DIR/OverLaunch.app"
python3 - "$BUILD_DIR/OverLaunch.app/Contents/Info.plist" <<'PY'
import json, plistlib, sys
info = plistlib.load(open(sys.argv[1], 'rb'))
assert info['OverLaunchReleaseVersion'] == json.load(open('release.json'))['artifactVersion'], 'Rebuild app for this release'
PY
STAGING="$BUILD_DIR/Package"
mkdir -p "$STAGING"
for PREVIOUS_APP in "$STAGING/OW120.app" "$STAGING/OverLaunch.app"; do
  if [[ -e "$PREVIOUS_APP" ]]; then rm -rf "$PREVIOUS_APP"; fi
done
cp -cR "$BUILD_DIR/OverLaunch.app" "$STAGING/OverLaunch.app"
ln -sfn /Applications "$STAGING/Applications"
cp RELEASE_NOTES.md "$STAGING/使用说明.md"
hdiutil create -volname OverLaunch -srcfolder "$STAGING" -ov -format UDZO "$BUILD_DIR/OverLaunch-$RELEASE_VERSION-arm64.dmg"
print "Packaged: $BUILD_DIR/OverLaunch-$RELEASE_VERSION-arm64.dmg"
