<div align="center">

# NotchPilot

**Your AI coding agents, living in the notch.**

Live status for **Claude Code**, **Codex** and **Cursor** sessions — glanceable, local, and one click from the right terminal.

[![CI](https://github.com/Nahast/NotchPilot/actions/workflows/ci.yml/badge.svg)](https://github.com/Nahast/NotchPilot/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Nahast/NotchPilot?include_prereleases&color=7c5cff)](https://github.com/Nahast/NotchPilot/releases)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![License: PolyForm Shield](https://img.shields.io/badge/source-PolyForm%20Shield%201.0.0-blue)](LICENSE)

[**Download**](https://github.com/Nahast/NotchPilot/releases) · [How it works](#-how-it-works) · [Privacy](#-privacy) · [Development](#-development)

</div>

---

## ✨ Features

| | |
|---|---|
| 🟢 **Live session list** | *Working*, *needs attention*, *idle/done* — each agent with its own brand-colored dot |
| 🔔 **Hard-to-miss alerts** | Pulse and optional auto-peek the moment an agent is waiting on you |
| 📊 **Context gauge** | % of the model's context window consumed, per session |
| ⚡ **Click to jump** | Focuses the matching iTerm2 window/tab, VS Code / Cursor, or the Claude desktop app |
| 🖥️ **Virtual notch** | No physical notch? A floating notch-shaped pill takes its place |
| 🔒 **Local by design** | No servers of ours, no telemetry — see [Privacy](#-privacy) |

## 📦 Install

1. Download the latest DMG from [Releases](https://github.com/Nahast/NotchPilot/releases).
2. Drag **NotchPilot** to Applications and launch it.
3. Onboarding walks through the one setup step (hooks) and the iTerm2 automation permission you'll see on the first jump.

Requires **macOS 13+**. Not sandboxed (it needs `~/.claude` access and Apple Events); distributed with Developer ID signing and notarization.

## 🔧 How it works

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

## 💻 Development

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
| `AgentCore` | Domain model: `AgentSession`, `AgentStatus`, `AgentProvider` protocol, `CompositeAgentProvider` |
| `ProviderCore` | Shared provider plumbing: FSEvents watching, JSONL tailing |
| `ClaudeCodeProvider` | Transcript watcher + hook-event watcher, JSONL parser, status state machine, desktop-app metadata |
| `CodexProvider` | Codex rollout transcripts (`~/.codex/sessions`), session-index names, token gauge |
| `CursorProvider` | Cursor hook events (`~/.cursor/hooks.json` → spool), hooks installer |
| `HookInstaller` | Idempotent merge of our hooks into `~/.claude/settings.json`, backups, clean uninstall |
| `JumpService` | Session → focus (Claude deep link, iTerm2 AppleScript, VS Code / Cursor activation) |
| `SettingsStore` | UserDefaults-backed preferences |
| `NotchUI` | Compact + expanded SwiftUI views behind a `NotchPresenter` protocol wrapping [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) |
| `NotchPilotApp` | App wiring, onboarding, settings window, Sparkle updates, demo mode |
| `NotchPilotHookHelper` | The `notchpilot-hook` micro-helper invoked by agent hooks |

New agents = new `AgentProvider` conformers; nothing else changes.

## 🔐 Privacy

All processing happens on your Mac. NotchPilot reads `~/.claude` (transcripts,
session registry, and settings) and the Claude desktop app's local session
store (for the session titles you see in its sidebar), and writes only to its
own Application Support folder plus the hooks entries in
`~/.claude/settings.json` (with backups).

Network traffic is limited to:

- the update check — Sparkle against GitHub Releases for direct installs; a
  build obtained from an app marketplace updates through that platform
  instead, and makes no Sparkle request;
- when "Show Claude usage limits" is enabled (default), Anthropic's usage
  endpoint — queried with Claude Code's own OAuth credentials, read from your
  Keychain after you approve the macOS permission prompt. Credentials are
  sent nowhere except `api.anthropic.com`. Turn the toggle off in Settings
  for zero Anthropic traffic.

## 📄 License

NotchPilot's source code is **source-available** under the
[PolyForm Shield License 1.0.0](LICENSE): you can read, build, modify and
use it freely — including at work — but you may not use it to provide a
product that competes with NotchPilot.

The compiled application distributed through Releases or an app marketplace
is governed by the [EULA](EULA.md). Bundled open-source components are listed
in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md). This is not an OSI-approved
open-source license.

Found a vulnerability? See [SECURITY.md](SECURITY.md).
