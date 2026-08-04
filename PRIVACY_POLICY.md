# NotchPilot Privacy Policy

**Effective date:** August 4, 2026 · **Version 1.1 (beta)**

NotchPilot is published by Romain Jouffret, operating as Warp Lab ("we", "us").
This policy describes exactly what data NotchPilot handles. The short version:
**NotchPilot is a local app. Your data stays on your Mac, we operate no
servers, and we never see it.**

## 1. Data Collected

NotchPilot's purpose is to display the status of AI coding agents already
running on your Mac. To do that it **reads** the following local files, all
processed in memory on your machine:

- **Claude Code** — transcripts, session registry, and settings under
  `~/.claude`; session titles and metadata from the Claude desktop app's
  local session store; hook events emitted by Claude Code.
- **Codex (OpenAI)** — session transcripts under `~/.codex/sessions` and the
  session name index `~/.codex/session_index.jsonl`.
- **Cursor** — hook events (conversation id, workspace path, edited file
  names) emitted by Cursor's hooks.

NotchPilot **stores** on your Mac, and nowhere else:

- Preferences (window options, per-agent connections) in macOS user defaults.
- Transient hook-event files and its helper binary under
  `~/Library/Application Support/NotchPilot/` (event files are deleted within
  seconds of being read).
- Timestamped backups of `~/.claude/settings.json` and `~/.cursor/hooks.json`
  made before any hook install/removal.

NotchPilot **transmits** in exactly two cases:

1. **Update check** — when NotchPilot is installed directly from us, it
   periodically contacts our release feed through the Sparkle framework to
   look for new versions. Standard HTTP request metadata (such as your IP
   address and app version) is visible to the hosting provider, as with any
   web request. No personal data or agent content is sent. When NotchPilot is
   obtained from an app marketplace, updates come through that platform's own
   mechanism instead and no Sparkle request is made.
2. **Claude usage limits (optional)** — if "Show Claude usage limits" is
   enabled, NotchPilot reads the OAuth token Claude Code itself stored in
   your macOS Keychain (macOS asks your permission first) and sends it only
   to Anthropic's API (`api.anthropic.com`) to fetch your rate-limit usage —
   the same call Claude Code makes. The token is never written anywhere by
   NotchPilot and never sent to any other party. Disable the toggle and this
   never happens.

**We do not collect analytics, telemetry, crash reports, usage statistics, or
any personal information. We do not operate servers that receive your data.
We do not share, sell, or disclose any data to third parties.** The only
parties that ever see network traffic from NotchPilot are Anthropic (when you
enable usage limits) and, for direct installs, the release-feed host (for
update checks).

## 2. Payments

NotchPilot is distributed free of charge, so there is nothing to pay for and
no payment details to collect. If optional paid functionality is offered in a
future version, the transaction is handled by the distribution platform you
got the app from (for example Apple), under that platform's own privacy
policy — we never receive or store your payment card details.

## 3. Your Control

- Disconnect any agent in Settings → Connected agents; its watchers stop and
  its hooks are removed.
- Remove all hooks in Settings → Agent hooks (backups are kept next to the
  original files).
- Delete `~/Library/Application Support/NotchPilot/` and the app itself to
  remove every trace.

## 4. Children

NotchPilot is a developer tool, not directed at children under 13, and
collects no data from anyone.

## 5. Changes

We may update this policy as the app evolves. Material changes will be noted
in the release notes; the current version always ships with the app and in
the source repository.

## 6. Contact

Questions or requests: **rjouffret@warp-lab.ai**
