# Releasing NotchPilot

One-time setup and per-release steps for shipping a signed, notarized DMG
with Sparkle auto-updates. Releases are published on the **Nahast** GitHub
account (`https://github.com/Nahast/NotchPilot`).

## One-time setup

### 1. Sparkle EdDSA keys

```bash
# The Sparkle tools live in the SwiftPM artifacts after a build:
SPARKLE_BIN=$(find .build/artifacts -type d -name bin -path "*sparkle*" | head -1)
"$SPARKLE_BIN/generate_keys"
```

`generate_keys` stores the private key in your login Keychain and prints the
public key. Put the public key into `Support/Info.plist` as `SUPublicEDKey`
(replacing the placeholder) and commit. **Never commit the private key.**

### 2. Developer ID certificate

Install your "Developer ID Application: …" certificate in the Keychain and
store notarytool credentials:

```bash
xcrun notarytool store-credentials notchpilot \
    --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
```

## Per release

```bash
# 1. Build, sign, package
export CODESIGN_IDENTITY="Developer ID Application: <name> (<team>)"
VERSION=0.2.0 BUILD_NUMBER=12 scripts/make_app.sh --universal
scripts/make_dmg.sh

# 2. Notarize + staple
xcrun notarytool submit dist/NotchPilot-0.2.0.dmg --keychain-profile notchpilot --wait
xcrun stapler staple dist/NotchPilot-0.2.0.dmg

# 3. Sparkle appcast
SPARKLE_BIN=$(find .build/artifacts -type d -name bin -path "*sparkle*" | head -1)
mkdir -p dist/appcast && cp dist/NotchPilot-0.2.0.dmg dist/appcast/
"$SPARKLE_BIN/generate_appcast" dist/appcast
# generate_appcast signs with the Keychain private key and writes appcast.xml

# 4. GitHub Release (Nahast account)
gh release create v0.2.0 dist/NotchPilot-0.2.0.dmg dist/appcast/appcast.xml \
    --title "NotchPilot 0.2.0" --notes "..."
```

The app's `SUFeedURL` points at
`https://github.com/Nahast/NotchPilot/releases/latest/download/appcast.xml`,
so attaching `appcast.xml` to the latest release is all Sparkle needs.

## Manual QA checklist (window layer)

Per the design spec, before each release check on real hardware:

- [ ] Notched MacBook: compact view hugs the notch; hover expands
- [ ] External display as main display: floating pill appears, hover expands
- [ ] Fullscreen app on the main display: notch window stays out of the way
- [ ] Sleep/wake and display plug/unplug: notch re-appears on the main display
- [ ] `--demo` mode renders 3 sessions with gauges for screenshots
- [ ] Onboarding: fresh run (`defaults delete com.rjouffret.NotchPilot`) shows
      consent; declining lands in limited mode; installing hooks flips the
      settings badge to green
- [ ] Jump: click a session → iTerm2 tab focused (first time: automation
      prompt); with iTerm2 closed → Claude Code desktop app activates
- [ ] Uninstall hooks from Settings → `~/.claude/settings.json` restored
      (verify with `git diff`-style comparison against the timestamped backup)
