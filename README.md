# NotchPilot

NotchPilot lives in your Mac's notch and shows the live status of your local
AI coding agent sessions. v1 monitors **Claude Code**; the provider
architecture keeps the door open for Cursor and Codex later.

- **Session list with live status** — *working*, *needs attention*, *idle/done*
- **Visible alert** (pulse + optional auto-peek) when an agent is waiting on you
- **Context gauge** per session — % of the model's context window consumed
- **Click to jump** — focuses the matching iTerm2 window/tab, or the Claude
  Code desktop app
- **Virtual notch** — on displays without a physical notch, a floating
  notch-shaped pill
- **100% local** — the only network traffic is the Sparkle update check

## How it works

Two complementary local sources; no sockets, no server, no telemetry:

1. **Hook events (reliable signal).** With your consent, NotchPilot registers
   Claude Code hooks (`SessionStart`, `Notification`, `Stop`, `SessionEnd`) in
   `~/.claude/settings.json` — a safe, reversible edit with a timestamped
   backup. Each hook runs a tiny bundled helper that drops a JSON event file
   into `~/Library/Application Support/NotchPilot/events/`, which the app
   watches with FSEvents.
2. **Transcript watching (activity + gauges).** NotchPilot tail-parses
   `~/.claude/projects/**/*.jsonl` to show the current activity ("Editing
   `main.swift`…") and the context-window gauge. The parser skips unknown
   line shapes, so Claude Code format drift degrades gracefully.

Declining the hooks leaves NotchPilot in **limited mode**: statuses are
estimated from transcript activity only, and labeled as such.

## Install

Download the latest DMG from Releases, drag NotchPilot to Applications, and
launch. Onboarding walks through the one setup step (hooks) and the iTerm2
automation permission you'll see on the first jump.

Requires macOS 13+. Not sandboxed (the app needs `~/.claude` access and Apple
Events), distributed outside the App Store with Developer ID signing and
notarization.

## Development

```bash
swift test                # unit + integration tests
swift run NotchPilot      # dev run (no bundle: Sparkle/launch-at-login off)
swift run NotchPilot --demo   # synthetic sessions for screenshots/QA
scripts/make_app.sh       # assemble dist/NotchPilot.app (ad-hoc signed)
scripts/make_dmg.sh       # package the DMG
scripts/make_icon.sh      # regenerate Support/AppIcon.icns
```

See [RELEASING.md](RELEASING.md) for signing, notarization, and Sparkle
appcast steps.

### Architecture

| Module | Responsibility |
|---|---|
| `AgentCore` | Domain model: `AgentSession`, `AgentStatus`, `AgentProvider` protocol |
| `ClaudeCodeProvider` | Transcript watcher + hook-event watcher, JSONL parser, status state machine |
| `HookInstaller` | Idempotent merge of our hooks into `~/.claude/settings.json`, backups, clean uninstall |
| `JumpService` | Session → focus (iTerm2 AppleScript, Claude Code desktop app) |
| `SettingsStore` | UserDefaults-backed preferences |
| `NotchUI` | Compact + expanded SwiftUI views behind a `NotchPresenter` protocol wrapping [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) |
| `NotchPilotApp` | App wiring, onboarding, settings window, Sparkle updates, demo mode |
| `NotchPilotHookHelper` | The `notchpilot-hook` micro-helper invoked by Claude Code hooks |

Cursor/Codex support later = new `AgentProvider` conformers; nothing else
changes.

## Privacy

All processing happens on your Mac. NotchPilot reads `~/.claude` (transcripts,
session registry, and settings) and the Claude desktop app's local session
store (for the session titles you see in its sidebar), and writes only to its
own Application Support folder plus the hooks entries in
`~/.claude/settings.json` (with backups).

Network traffic is limited to:

- the Sparkle update check against GitHub Releases;
- when "Show Claude usage limits" is enabled (default), Anthropic's usage
  endpoint — queried with Claude Code's own OAuth credentials, read from your
  Keychain after you approve the macOS permission prompt. Credentials are
  sent nowhere except `api.anthropic.com`. Turn the toggle off in Settings
  for zero Anthropic traffic.
