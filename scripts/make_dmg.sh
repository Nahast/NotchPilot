#!/bin/bash
# Packages dist/NotchPilot.app into a distributable DMG.
# Run scripts/make_app.sh first (usually with --universal and a real identity).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/NotchPilot.app"
[[ -d "$APP" ]] || { echo "error: $APP missing — run scripts/make_app.sh first" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/NotchPilot-$VERSION.dmg"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "NotchPilot" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY}" != "-" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"
fi

echo "OK: $DMG"
