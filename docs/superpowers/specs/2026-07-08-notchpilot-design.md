# NotchPilot — Design Spec

**Date:** 2026-07-08
**Status:** Approved by Romain (brainstorming session)
**Product:** NotchPilot — a macOS notch app that monitors AI coding agents.
**Inspiration:** https://www.agentnotch.app/ (agent monitoring from the notch). NotchPilot is an independent product; no assets, code, or name from AgentNotch are used.

## 1. Goal & scope

NotchPilot floats where the notch is on macOS and shows the live status of local
AI coding agent sessions. v1 monitors **Claude Code only**; the architecture
keeps the door open for Cursor and Codex providers later.

**In scope (v1):**

- Session list with live status: *working*, *needs attention*, *idle/done*
- Visible alert when a session is waiting on the user
- Per-session context-usage gauge
- Click a session to jump to it (iTerm2 and the Claude Code desktop app —
  Romain's environments)
- Virtual notch on displays without a physical notch
- Distributable from day one: Developer ID signed, notarized DMG, Sparkle 2
  auto-updates, app icon, onboarding
- 100% local processing; the only network traffic is the Sparkle update check

**Out of scope (v1):**

- Inline approvals (answering permission prompts from the notch)
- Cursor / Codex providers
- Subagent activity display
- Mac App Store distribution (app needs `~/.claude` access and Apple Events;
  it is not sandboxed)

## 2. UX & product behavior

### Compact state (always present)

Top-center of the screen: hugs the real notch on notched MacBooks; on other
displays (external monitors, non-notched Macs) draws a floating notch-shaped
pill via DynamicNotchKit's `.floating` style. Shows the minimum useful signal —
a dot + count per status class, e.g. `● 2` (green, working) `● 1` (orange,
needs attention). All idle → single dim glyph. When any session flips to
*needs attention*, the compact view pulses orange; optionally the panel
auto-peeks for a few seconds (setting, default on).

### Expanded state (on hover)

Hovering expands a panel below the notch. One row per session:

- Project name (folder name of the session's working directory)
- Status icon (working = animated, needs attention = orange, idle/done = gray
  or green check)
- One-line current activity: last tool use ("Editing `main.swift`…",
  "Running tests…") or "Waiting for your approval"
- Context gauge: thin bar/ring showing % of the model's context window consumed
- Time in current state ("waiting 3m")

Clicking a row jumps to that session. Mouse-out collapses. Gear icon opens
Settings (launch at login, auto-peek toggle, staleness timeout, check for
updates).

### First run / onboarding

Explains what the app does and asks consent for the one setup step: installing
Claude Code hooks (a safe, reversible edit to `~/.claude/settings.json`).
Declining leaves the app in transcript-only "limited mode" (see §4). Onboarding
also warns that the first jump-to-iTerm2 triggers the macOS automation
permission prompt. If `~/.claude` does not exist, show "Claude Code not
detected" guidance instead of an empty state.

## 3. Architecture

Single SwiftUI app target, `LSUIElement` (no dock icon), macOS 13+, plus one
bundled micro-helper for hook events. Not sandboxed. Distribution is Developer
ID + notarization outside the App Store.

**Key dependency:** [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)
(MIT, macOS 13+, actively maintained — 1.1.0 April 2026) for the notch window
mechanics: always-on-top notch-hugging panel, hover interaction, expansion
animation, `.floating` virtual notch on non-notched displays.

### Modules

| Module | Responsibility | Depends on |
|---|---|---|
| **NotchUI** | Compact + expanded SwiftUI views; `NotchPresenter` protocol wrapping DynamicNotchKit so it can be swapped/forked without touching other modules | DynamicNotchKit, AgentCore |
| **AgentCore** | Domain model: `AgentSession` (id, project path, status, current activity, context usage, timestamps); `AgentProvider` protocol publishing `[AgentSession]` | — |
| **ClaudeCodeProvider** | v1 `AgentProvider`: transcript watcher + hook-event watcher, JSONL parser, status state machine | AgentCore |
| **HookInstaller** | Idempotent merge of our hooks into `~/.claude/settings.json`; timestamped backup before write; clean uninstall | — |
| **JumpService** | Session → focus. iTerm2: AppleScript, find window/tab matching the project path. Claude Code desktop app: activate app (best effort). Fallback: activate app only | AgentCore |
| **SettingsStore** | UserDefaults-backed preferences | — |
| **UpdateService** | Sparkle 2, appcast on GitHub Releases | — |
| **LaunchAtLogin** | SMAppService | — |

Cursor/Codex support later = new `AgentProvider` conformers; nothing else
changes.

## 4. Data flow & status detection

Two complementary local sources. No sockets, no server, no network.

### Hook events (reliable signal)

With user consent, register Claude Code hooks: `SessionStart`, `Notification`
(Claude needs permission / waits for input), `Stop` (turn finished),
`SessionEnd`. Each hook invokes a bundled micro-helper that writes one small
JSON event file into `~/Library/Application Support/NotchPilot/events/`. The
app watches that directory with FSEvents and updates state instantly.

### Transcript watching (activity + gauges)

FSEvents on `~/.claude/projects/**/*.jsonl`, incremental tail-parse of appended
lines. Yields current activity (last `tool_use` name/target) and the context
gauge (latest assistant message token usage vs. the model's context window).
The parser is tolerant: unknown line shapes are skipped so Claude Code format
drift degrades gracefully (e.g. gauge hides if usage fields disappear) instead
of crashing.

### Status state machine (per session)

| Event | New status |
|---|---|
| `SessionStart` hook | working |
| `Notification` hook | needs attention |
| transcript advances again | working |
| `Stop` hook | idle (done) |
| `SessionEnd` hook or staleness timeout (default 30 min, configurable) | session removed |

**Limited mode (hooks declined/unavailable):** transcript heuristics only —
recent writes = working; mid-turn stall = probably waiting. UI labels this
"limited mode".

## 5. Edge cases & error handling

- **No `~/.claude`** → "Claude Code not detected" onboarding state.
- **`settings.json` editing** — parse-validate first; timestamped backup;
  merge without touching existing hooks; if malformed, refuse to write and fall
  back to limited mode rather than risk breaking the user's Claude Code setup.
- **Crashed CLI / missing `SessionEnd`** → staleness timeout reaps the session.
- **Display changes / sleep-wake / fullscreen** → DynamicNotchKit re-tracks
  geometry; re-render on `NSScreen` change notifications. v1 shows on the main
  display (the one with the menu bar); "follow mouse" is a possible later
  option.
- **Many sessions** → expanded panel caps height and scrolls; compact view
  shows counts only.
- **Jump failures** (window closed, automation permission denied) → fall back
  to activating the app.

## 6. Distribution & privacy

- Developer ID signing, hardened runtime, notarization (Romain's Apple
  Developer account at release time), DMG packaging.
- Sparkle 2 auto-updates; appcast hosted on GitHub Releases.
- App icon, onboarding, launch-at-login toggle.
- Privacy: 100% local processing. The only network traffic is the Sparkle
  update check, stated plainly in the app and README.

## 7. Testing

- **Unit:** JSONL parser vs. fixture transcripts recorded from real sessions;
  state machine vs. scripted event sequences; hook-merge idempotency (apply
  twice → identical file; uninstall → original restored).
- **Integration:** provider pointed at a fake `~/.claude` fixture tree; inject
  spool events; assert the published session list.
- **Manual QA checklist** for the window layer: notched MacBook, external
  display, fullscreen apps, sleep/wake.
- **Demo mode** (hidden flag) feeds synthetic sessions for screenshots and QA.

## 8. Decisions log

| Decision | Choice | Why |
|---|---|---|
| Purpose | AI agent monitor (AgentNotch-style) | User choice |
| Agents in v1 | Claude Code only | Richest local data; provider protocol keeps Cursor/Codex open |
| Feature scope | Status + alerts + gauges; no inline approvals | Approvals require injecting input into sessions — deferred |
| No-notch displays | Virtual notch everywhere | Works in clamshell/external-monitor setups |
| Terminals for jump | Claude Code desktop app + iTerm2 | Romain's environments |
| Distribution | Distributable from day one | User choice |
| Stack | Native SwiftUI + DynamicNotchKit | Lightweight always-on utility; MIT lib solves notch mechanics |
| Hook transport | JSON event files in Application Support, FSEvents-watched | No networking, simple, sandbox-friendly, robust |
| Name | NotchPilot (bundle id `com.rjouffret.NotchPilot`) | User choice |
