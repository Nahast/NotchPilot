# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app (Swift Package: AppKit + SwiftUI, no Xcode project). macOS 13+,
menu-bar/accessory app (`LSUIElement`) with no dock icon or standard window.

## Users

Developers who keep AI coding agents — Claude Code, Codex (OpenAI), Cursor —
running through the workday, often several at once across projects, and lose
track of which agent is working, which finished, and which is silently blocked
waiting for their approval. They live in a terminal (iTerm2) and/or the Claude
desktop app; NotchPilot is glanced at, not operated. Broad public audience via
free distribution, not an internal tool.

## Product Purpose

Ambient, glanceable status for local AI agent sessions, surfaced in the Mac's
notch (or a floating notch-shaped pill on displays without one). Success is the
user never discovering "the agent has been waiting on me for 20 minutes" —
the needs-attention moment is visible the second it happens, and one click
jumps to the exact conversation.

## Positioning

**The notch placement is the product.** Always-visible ambient status in dead
screen space: no dock icon, no window to manage, no attention cost until an
agent needs you. Local-first privacy and multi-agent coverage support the
claim but the glanceable notch is the thing a menu-bar utility or dashboard
cannot truthfully copy.

## Operating Context

- Reads agents' own local state: `~/.claude` (transcripts, session registry,
  settings), the Claude desktop app's session store, `~/.codex` rollouts and
  session index, Cursor hook events.
- With consent, registers hooks in `~/.claude/settings.json` and
  `~/.cursor/hooks.json` (timestamped backups; reversible) that run a tiny
  bundled helper — the authoritative "needs attention"/"done" signal.
- Click-to-jump drives iTerm2 via AppleScript (Apple Events) or deep-links
  into the Claude desktop app.
- Optional usage gauge calls Anthropic's usage endpoint with Claude Code's
  own OAuth token read from the user's Keychain (macOS consent prompt).

## Capabilities and Constraints

- Session list with live status (working / needs attention / idle), per-model
  context gauge, daily token tally, PR badges, session titles matching what
  the user's terminal or Claude app sidebar shows.
- Compact view: one brand-colored dot per running agent, capped at 4.
- Demo mode (`--demo`) feeds synthetic sessions for screenshots/QA.
- Sparkle auto-updates from GitHub Releases (Developer ID channel).
- **Distribution: Developer ID–signed, notarized DMG outside the App Store.**
  A 2026-08-04 audit found Mac App Store distribution infeasible for the full
  product: the App Sandbox and Guidelines 2.4.5(i)/(v) prohibit the hook
  pipeline (installing/registering a helper another app executes), and no
  entitlement covers reading another vendor's Keychain item. An App Store
  build is possible only as a deliberately reduced SKU (read-only monitoring;
  no hooks, no Cursor, no usage gauge, no Sparkle). **Open decision:** whether
  that reduced SKU is worth shipping alongside the DMG.
- Free of charge today; EULA v1.1 reserves optional paid functionality later,
  with payments handled by the distribution platform.

## Brand Commitments

- Name: NotchPilot. Publisher: Romain Jouffret, operating as Warp Lab.
  Contact: rjouffret@warp-lab.ai. Releases under the Nahast GitHub account.
- Per-agent brand-colored dots give each agent its identity in the compact
  view.
- Tone of shipped copy (README, legal, UI): plain, factual, non-corporate.

## Evidence on Hand

- Working product: 171+ passing tests, real multi-agent monitoring verified
  against live sessions on the author's machine.
- EULA.md and PRIVACY_POLICY.md v1.1 (2026-08-04), rendered in-app.
- No testimonials, user counts, benchmarks, or press — nothing of that kind
  may be fabricated for marketing surfaces.

## Product Principles

1. **Glanceable over informative.** The notch earns its place by costing zero
   attention until something needs the user; density and dashboards are
   failure modes.
2. **Never lie about status.** Hook-driven state is ground truth; heuristic
   guesses are visibly labeled ("limited mode", "Probably waiting on you").
   A wrong "all clear" is the worst defect the product can ship.
3. **Local-first is binding, forever.** No telemetry, no analytics, no crash
   reporting that phones home — even in future paid versions. Diagnostics are
   local and user-initiated. The only network traffic is the update check and
   the user-enabled Anthropic usage call. Confirmed as a permanent commitment
   by the owner, 2026-08-04.
4. **Guest in other apps' homes.** Every touch of another tool's files is
   consented, reversible, and backed up; degrade gracefully (don't break) when
   those tools change.
5. **The agent's own name.** Sessions are named what the user sees in the
   agent's own UI — terminal tab, sidebar — never an internal slug.

## Accessibility & Inclusion

Status is currently conveyed by color alone (brand-colored dots) and no
controls carry accessibility labels — both known gaps, queued behind release
blockers. Direction: pair every color-coded state with a non-color cue and
label all controls for VoiceOver.
