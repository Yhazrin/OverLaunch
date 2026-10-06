#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
: "${OW120_SIGN_IDENTITY:?Set a Developer ID Application identity}"
: "${OW120_NOTARY_PROFILE:?Set an existing notarytool keychain profile}"
if [[ "$OW120_SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
  print -u2 'Public notarization requires Developer ID Application, not Apple Development or ad-hoc signing.'; exit 1
fi
./scripts/build.sh
APP="$PROJECT_DIR/dist.noindex/OverLaunch.app"
ZIP="$PROJECT_DIR/dist.noindex/OverLaunch-notary.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
submit_and_check() {
  local artifact="$1"
  local receipt="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$OW120_NOTARY_PROFILE" --wait --timeout 30m --output-format json > "$receipt"
  python3 - "$receipt" <<'PYNOTARY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization not Accepted; inspect the local receipt and notarytool log before retrying.')
print('Notarization Accepted')
PYNOTARY
}
submit_and_check "$ZIP" "$PROJECT_DIR/dist.noindex/app-notary-result.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"
./scripts/package.sh --no-build
RELEASE_VERSION="$(python3 -c 'import json; print(json.load(open("release.json"))["artifactVersion"])')"
DMG="$PROJECT_DIR/dist.noindex/OverLaunch-$RELEASE_VERSION-arm64.dmg"
codesign --force --sign "$OW120_SIGN_IDENTITY" --timestamp "$DMG"
submit_and_check "$DMG" "$PROJECT_DIR/dist.noindex/dmg-notary-result.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
print "Notarized: $DMG"
