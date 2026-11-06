#!/bin/bash
# Ad-hoc signed developer preview; does not notarize or publish.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/dist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' script/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' script/Info.plist)
NAME="ICS-Harbor-${VERSION}-preview.${BUILD}-arm64"
TEMP_STAGE="$(mktemp -d "$ROOT/dist/.harbor-dmg.XXXXXX")"
trap 'rm -rf "$TEMP_STAGE"' EXIT
STAGE="$TEMP_STAGE/stage"
mkdir -p "$STAGE/docs"
HARBOR_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only "$STAGE"
ln -s /Applications "$STAGE/Applications"
cp README.md LICENSE THIRD_PARTY_NOTICES.md "$STAGE/"
cp docs/ARCHITECTURE.md docs/PARAMETERS.md docs/VALIDATION.md "$STAGE/docs/"
codesign --verify --deep --strict "$STAGE/Harbor.app"
plutil -lint "$STAGE/Harbor.app/Contents/Info.plist"
hdiutil create -volname "ICS-Harbor ${VERSION} Preview" -srcfolder "$STAGE" -format UDZO -ov "$TEMP_STAGE/$NAME.dmg"
hdiutil verify "$TEMP_STAGE/$NAME.dmg"
mv "$TEMP_STAGE/$NAME.dmg" "$ROOT/dist/$NAME.dmg"
(cd "$ROOT/dist" && shasum -a 256 "$NAME.dmg") > "$ROOT/dist/$NAME.dmg.sha256"
printf 'DMG: %s\nAd-hoc signed; not notarized.\n' "$ROOT/dist/$NAME.dmg"
