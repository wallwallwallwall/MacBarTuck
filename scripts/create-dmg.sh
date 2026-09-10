#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BarTuck/Resources/Info.plist")"
DERIVED_DATA="$ROOT/work/DerivedData-Release"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/BarTuck-dmg.XXXXXX")"
STAGING="$TEMP_ROOT/dmg-root"
DIST="$ROOT/dist"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/BarTuck.app"
APP_STAGED="$STAGING/BarTuck.app"
DMG_NAME="BarTuck-$VERSION.dmg"
DMG_PATH="$DIST/$DMG_NAME"

trap 'rm -rf "$TEMP_ROOT"' EXIT INT TERM

rm -rf "$DERIVED_DATA"
mkdir -p "$STAGING/.background" "$DIST"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

xcodebuild \
  -project "$ROOT/BarTuck.xcodeproj" \
  -scheme BarTuck \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

test -d "$APP_SOURCE"
ditto --norsrc "$APP_SOURCE" "$APP_STAGED"
# Builds created inside a File Provider-backed Documents folder can inherit
# Finder metadata that ad-hoc signing rejects. Only clean the disposable DMG
# staging copy; the source tree and build product remain untouched.
xattr -cr "$APP_STAGED"

ARCHS_FOUND="$(lipo -archs "$APP_STAGED/Contents/MacOS/BarTuck")"
if [[ "$ARCHS_FOUND" != "arm64" ]]; then
  print -u2 "Unexpected executable architectures: $ARCHS_FOUND"
  exit 1
fi

codesign --force --deep --sign - --timestamp=none "$APP_STAGED"
codesign --verify --deep --strict --verbose=2 "$APP_STAGED"

ln -s /Applications "$STAGING/Applications"
ditto --norsrc "$ROOT/docs/INSTALL.txt" "$STAGING/INSTALL.txt"
ditto --norsrc "$ROOT/README.md" "$STAGING/README.md"
ditto --norsrc "$ROOT/PRIVACY.md" "$STAGING/PRIVACY.md"
ditto --norsrc "$ROOT/LICENSE" "$STAGING/LICENSE"
ditto --norsrc "$ROOT/NOTICE" "$STAGING/NOTICE"

swift "$ROOT/scripts/make-dmg-background.swift" "$STAGING/.background/background.png"
xattr -cr "$STAGING"
codesign --verify --deep --strict --verbose=2 "$APP_STAGED"

hdiutil create \
  -volname "BarTuck $VERSION" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

(
  cd "$DIST"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
  shasum -a 256 -c "$DMG_NAME.sha256"
)

print "Created $DMG_PATH"
print "Created $DMG_PATH.sha256"
