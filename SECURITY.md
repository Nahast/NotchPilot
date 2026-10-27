# Security Policy

## Reporting a vulnerability

Please **do not open a public issue**. Report privately via GitHub's
[private vulnerability reporting](https://github.com/Nahast/NotchPilot/security/advisories/new),
or email **rjouffret@warp-lab.ai**.

Include the affected version, reproduction steps, and impact. Expect an
acknowledgement within a few days.

## Scope

NotchPilot runs locally, has no server, and reads agent session data and
Claude Code's Keychain token on your machine. Of particular interest: token
or transcript leakage, unsafe edits to `~/.claude/settings.json`, command or
AppleScript injection via session paths, and update-feed (Sparkle) integrity.

## Supported versions

Only the latest release receives fixes.
