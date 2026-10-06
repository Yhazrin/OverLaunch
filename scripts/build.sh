#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
./scripts/fetch-vendor.sh
python3 scripts/fetch-hero-assets.py
swift build -c release
BUILD_DIR="$PROJECT_DIR/dist.noindex"
mkdir -p "$BUILD_DIR"
# Development bundles must not become extra application-grid entries.
# Keep the old CLI/documentation path as a compatibility link.
if [[ ! -e "$PROJECT_DIR/dist" && ! -L "$PROJECT_DIR/dist" ]]; then
  ln -s dist.noindex "$PROJECT_DIR/dist"
fi
APP="$BUILD_DIR/OverLaunch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/OW120" "$APP/Contents/MacOS/OW120"
SDK_PATH="$(xcrun --show-sdk-path)"
CLANG_PATH="$(xcrun --find clang)"
"$CLANG_PATH" -arch arm64 -arch x86_64 -isysroot "$SDK_PATH" -mmacosx-version-min=14.0 -fobjc-arc \
  scripts/diagnostics/metal-smoke.m -framework Foundation -framework Metal -framework AppKit -framework QuartzCore \
  -o "$APP/Contents/MacOS/OW120GraphicsProbe"
codesign --force --sign "${OW120_SIGN_IDENTITY:--}" "$APP/Contents/MacOS/OW120GraphicsProbe"
cp Vendor/dxmt-ow2-pack-v0.2.tar.gz "$APP/Contents/Resources/"
cp THIRD_PARTY.md "$APP/Contents/Resources/"
cp Vendor/DXMT-LICENSE Vendor/DXMT-COPYING.LIB "$APP/Contents/Resources/"
python3 scripts/verify-hero-assets.py
mkdir -p "$APP/Contents/Resources/HeroIcons"
cp -R Assets/HeroIcons/. "$APP/Contents/Resources/HeroIcons/"
python3 scripts/verify-font-assets.py
mkdir -p "$APP/Contents/Resources/Fonts"
cp Assets/Fonts/SmileySans-Oblique.otf Assets/Fonts/OFL.txt Assets/Fonts/manifest.json "$APP/Contents/Resources/Fonts/"
swift scripts/make-icon.swift "$BUILD_DIR/OW120.iconset"
iconutil -c icns "$BUILD_DIR/OW120.iconset" -o "$APP/Contents/Resources/OW120.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OW120</string>
<key>CFBundleIdentifier</key><string>local.ow120.launcher</string>
<key>CFBundleName</key><string>OverLaunch</string>
<key>CFBundleDisplayName</key><string>OverLaunch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.4</string>
<key>CFBundleVersion</key><string>14</string>
<key>CFBundleIconFile</key><string>OW120</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSDocumentsFolderUsageDescription</key><string>复用已有守望先锋设置，并在独立目录中创建游戏配置。</string>
</dict></plist>
PLIST
# A build can override the public project address when needed.
python3 - "$APP/Contents/Info.plist" <<'PY'
import os, plistlib, sys
from urllib.parse import urlparse
address = os.environ.get('OVERLAUNCH_REPOSITORY_URL', 'https://github.com/Yhazrin/OverLaunch').strip()
if address:
    if urlparse(address).scheme != 'https' or not urlparse(address).netloc:
        raise SystemExit('OVERLAUNCH_REPOSITORY_URL must be an HTTPS project URL')
    path = sys.argv[1]
    with open(path, 'rb') as file:
        info = plistlib.load(file)
    info['OverLaunchRepositoryURL'] = address
    with open(path, 'wb') as file:
        plistlib.dump(info, file)
PY
codesign --force --sign "${OW120_SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
print "Built: $APP"
