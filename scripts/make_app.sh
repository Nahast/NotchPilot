#!/bin/bash
# Builds NotchPilot.app into dist/.
#
# Usage:
#   scripts/make_app.sh                 # host-arch, ad-hoc signed (dev)
#   scripts/make_app.sh --universal     # arm64 + x86_64 (release)
#
# Environment:
#   CODESIGN_IDENTITY  "Developer ID Application: ..." (default: the local
#                      Apple Development identity, else "-" ad-hoc)
#   VERSION            marketing version (default: from Support/Info.plist)
#   BUILD_NUMBER       CFBundleVersion (default: from Support/Info.plist)
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0
[[ "${1:-}" == "--universal" ]] && UNIVERSAL=1
# An ad-hoc signature has no team identifier, so its designated requirement is
# pinned to the exact binary hash: every rebuild produces a "different app" and
# silently voids per-app grants the user has made — Keychain ACL entries,
# Accessibility, Automation. That is why a dev build kept re-asking for
# Keychain access. Prefer any stable local identity so those grants survive.
#
# Note: the lookup deliberately uses `find-identity -v` rather than the
# stricter `-v codesigning` policy, which reports 0 identities on machines
# where codesign itself signs perfectly well.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITIES=$(security find-identity -v 2>/dev/null)
    for prefix in "Developer ID Application" "Apple Development"; do
        IDENTITY=$(sed -n "s/.*\"\($prefix:.*\)\"/\1/p" <<<"$IDENTITIES" | head -1)
        [[ -n "$IDENTITY" ]] && break
    done
fi
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "warning: no signing identity found — signing ad-hoc. macOS will" >&2
    echo "         re-ask for Keychain access after every rebuild." >&2
fi

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
cp Support/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
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
# which rejects ad-hoc-signed frameworks — so only enable it for the Developer
# ID builds that actually get notarized; dev builds sign without it.
SIGN_FLAGS=()
if [[ "$IDENTITY" == "Developer ID"* ]]; then
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
# Only the app itself sends Apple Events (click-to-jump drives iTerm2), so the
# entitlement goes on the app and nothing else. Ad-hoc builds skip it: they
# carry no team identity for the entitlement to be attributed to.
APP_SIGN_FLAGS=("${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}")
if [[ "$IDENTITY" != "-" ]]; then
    APP_SIGN_FLAGS+=(--entitlements Support/NotchPilot.entitlements)
fi
codesign --force "${APP_SIGN_FLAGS[@]+"${APP_SIGN_FLAGS[@]}"}" --sign "$IDENTITY" "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
# The failure this guards against is invisible at build time and only shows up
# as a silently dead "click to jump" on a user's machine, so assert it here
# rather than trusting the flags above stayed in place.
if [[ "$IDENTITY" != "-" ]]; then
    if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null \
        | plutil -convert xml1 -o - - 2>/dev/null \
        | grep -q "com.apple.security.automation.apple-events"; then
        echo "error: the Apple Events entitlement is missing from the signed app —" >&2
        echo "       click-to-jump would fail silently under the hardened runtime." >&2
        exit 1
    fi
    echo "==> Apple Events entitlement present"
fi

# Smoke check: the signed binary must actually launch and load its
# frameworks. Catches rpath/embedding mistakes that codesign can't.
if ! SMOKE_OUT=$("$APP/Contents/MacOS/NotchPilot" --smoke-test 2>&1); then
    echo "error: smoke test failed — the built app does not launch:" >&2
    echo "$SMOKE_OUT" >&2
    exit 1
fi
echo "==> Smoke test: $SMOKE_OUT"
echo "OK: $APP"
