#!/bin/bash
# Builds NotchPilot.app into dist/.
#
# Usage:
#   scripts/make_app.sh                 # host-arch, ad-hoc signed (dev)
#   scripts/make_app.sh --universal     # arm64 + x86_64 (release)
#
# Environment:
#   CODESIGN_IDENTITY  "Developer ID Application: ..." (default: "-" ad-hoc)
#   VERSION            marketing version (default: from Support/Info.plist)
#   BUILD_NUMBER       CFBundleVersion (default: from Support/Info.plist)
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "==> Building (release$([[ $UNIVERSAL == 1 ]] && echo ", universal"))"
if [[ $UNIVERSAL == 1 ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)"
fi

APP="dist/NotchPilot.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$APP/Contents/Frameworks" "$APP/Contents/Helpers"

cp "$BIN/NotchPilot" "$APP/Contents/MacOS/NotchPilot"
cp "$BIN/notchpilot-hook" "$APP/Contents/Helpers/notchpilot-hook"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Legal documents shown from Settings.
cp PRIVACY_POLICY.md "$APP/Contents/Resources/PRIVACY_POLICY.md"
cp EULA.md "$APP/Contents/Resources/EULA.md"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

echo "==> Embedding Sparkle.framework"
SPARKLE_FW=$(find .build -type d -name "Sparkle.framework" -path "*artifacts*" | head -1)
if [[ -z "$SPARKLE_FW" ]]; then
    echo "error: Sparkle.framework not found under .build/artifacts — run swift build first" >&2
    exit 1
fi
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"

echo "==> Codesigning (identity: $IDENTITY)"
# Hardened runtime (required for notarization) enforces library validation,
# which rejects ad-hoc-signed frameworks — so only enable it with a real
# Developer ID identity; ad-hoc dev builds sign without it.
SIGN_FLAGS=()
if [[ "$IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime)
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
# Sign Sparkle's nested executables first, then the framework, helper, app.
for nested in \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
    "$FRAMEWORK/Versions/B/Autoupdate" \
    "$FRAMEWORK/Versions/B/Updater.app"; do
    [[ -e "$nested" ]] && codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" "$nested"
done
codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" "$FRAMEWORK"
codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" "$APP/Contents/Helpers/notchpilot-hook"
codesign --force "${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}" --sign "$IDENTITY" "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
echo "OK: $APP"
