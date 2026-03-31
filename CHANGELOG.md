# Changelog

All notable changes to GitHub Command Center will be documented in this file.

## [0.1.0] - 2026-03-31

Initial MVP release. A macOS menu bar app that monitors your GitHub PRs and tells you what needs attention.

### Added

- **PR triage dashboard** in the menu bar — PRs are split into "Needs Your Action", "Waiting on Others", and "Your Drafts" so you always know what to look at first
- **Smart attention badge** — the menu bar icon shows how many PRs need your action, not the total count
- **Status dots** with click popovers showing CI, review, and merge status for each PR at a glance
- **Real-time notifications** for CI failures on your PRs, review requests, changes requested, approval, and merge conflicts
- **Adaptive polling** — polls every 60s for small workloads, backs off to 5min for large ones, with ETag caching to minimize API usage
- **Rate limit awareness** — detects GitHub API rate limits and pauses polling with a recovery timer
- **Token validation** — checks that your PAT has the right scopes and warns about missing permissions
- **Environment token bootstrapper** — automatically loads tokens from `GITHUB_TOKEN`, `GH_TOKEN`, or `.env.local` files during development
- **Inline settings panel** — configure your token and manage repos without leaving the menu bar popover
- **Draft PR section** — your drafts are tracked separately so they don't clutter the action list
- **Pagination safety** — caps API pagination to prevent runaway requests on very active accounts
- **Keychain storage** with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for secure token persistence
- **Notification threading** — PR notifications are grouped under a shared thread identifier

### Changed

- Menu bar icon animates during initial load to show the app is working

### Fixed

- CI notification fires correctly on pending-to-failing transitions (not just passing-to-failing)
- Check-run API 403/404 falls back gracefully instead of failing the entire PR fetch
- Thread-safe access to notification handlers, date formatters, and mock test infrastructure
- Unterminated quoted tokens in `.env` files are rejected instead of silently truncated
