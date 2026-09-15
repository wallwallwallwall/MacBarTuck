#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/MacBarTuck/Resources/Info.plist")"
DERIVED_DATA="$ROOT/work/DerivedData-Release"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/MacBarTuck-dmg.XXXXXX")"
STAGING="$TEMP_ROOT/dmg-root"
DIST="$ROOT/dist"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/MacBarTuck.app"
APP_STAGED="$STAGING/MacBarTuck.app"
DMG_NAME="MacBarTuck-$VERSION.dmg"
DMG_PATH="$DIST/$DMG_NAME"
SIGNING_IDENTITY="${MACBARTUCK_SIGNING_IDENTITY:-${BARTUCK_SIGNING_IDENTITY:--}}"

trap 'rm -rf "$TEMP_ROOT"' EXIT INT TERM

test -x "$XCODEBUILD"
test -x "$SWIFT"
test -d "$SDKROOT"

rm -rf "$DERIVED_DATA"
mkdir -p "$STAGING/.background" "$STAGING/docs" "$DIST"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

DEVELOPER_DIR="$DEVELOPER_DIR" "$XCODEBUILD" \
  -project "$ROOT/MacBarTuck.xcodeproj" \
  -scheme MacBarTuck \
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

ARCHS_FOUND="$(lipo -archs "$APP_STAGED/Contents/MacOS/MacBarTuck")"
if [[ "$ARCHS_FOUND" != "arm64" ]]; then
  printf 'Unexpected executable architectures: %s\n' "$ARCHS_FOUND" >&2
  exit 1
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --timestamp=none "$APP_STAGED"
else
  codesign --force --deep --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP_STAGED"
fi
codesign --verify --deep --strict --verbose=2 "$APP_STAGED"

ln -s /Applications "$STAGING/Applications"
ditto --norsrc "$ROOT/docs/INSTALL.txt" "$STAGING/INSTALL.txt"
ditto --norsrc "$ROOT/README.md" "$STAGING/README.md"
ditto --norsrc "$ROOT/PRIVACY.md" "$STAGING/PRIVACY.md"
ditto --norsrc "$ROOT/LICENSE" "$STAGING/LICENSE"
ditto --norsrc "$ROOT/NOTICE" "$STAGING/NOTICE"
ditto --norsrc "$ROOT/docs/runtime-qa.md" "$STAGING/docs/runtime-qa.md"
ditto --norsrc "$ROOT/docs/open-source-references.md" "$STAGING/docs/open-source-references.md"
ditto --norsrc "$ROOT/docs/interface-refresh.md" "$STAGING/docs/interface-refresh.md"
ditto --norsrc "$ROOT/docs/app-access.md" "$STAGING/docs/app-access.md"
ditto --norsrc "$ROOT/docs/permissions.md" "$STAGING/docs/permissions.md"
ditto --norsrc "$ROOT/docs/layout-stability.md" "$STAGING/docs/layout-stability.md"
ditto --norsrc "$ROOT/docs/hidden-state.md" "$STAGING/docs/hidden-state.md"
ditto --norsrc "$ROOT/design-qa.md" "$STAGING/design-qa.md"
mkdir -p "$STAGING/docs/screenshots"
for screenshot in "$ROOT"/docs/screenshots/*.png; do
  ditto --norsrc "$screenshot" "$STAGING/docs/screenshots/$(basename "$screenshot")"
done

DEVELOPER_DIR="$DEVELOPER_DIR" SDKROOT="$SDKROOT" \
  "$SWIFT" "$ROOT/scripts/make-dmg-background.swift" "$STAGING/.background/background.png"
xattr -cr "$STAGING"
codesign --verify --deep --strict --verbose=2 "$APP_STAGED"

hdiutil create \
  -volname "MacBarTuck $VERSION" \
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

printf 'Created %s\n' "$DMG_PATH"
printf 'Created %s\n' "$DMG_PATH.sha256"
