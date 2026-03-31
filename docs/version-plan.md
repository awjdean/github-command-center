# Version Plan

## MVP (v0.1) — Core PR Triage ✅ (in progress)

**Goal:** Functional menu bar app that shows PR status at a glance.

### Features shipped
- Menu bar icon showing number of PRs needing attention
- Dropdown with PRs split into three triage sections: Needs Your Action / Waiting on Others / Your Draft PRs
- Per-PR indicators: review state, CI status, merge status
- Click PR number → opens GitHub URL in browser
- Loading state on app start
- Settings: GitHub token entry/removal, tracked repos (collapsible), Launch at Login, Quit
- CI failure details in info popup
- Instant tooltip display on indicator click

### Remaining MVP items
- [ ] Notifications (including sound) when a tracked PR changes status — *manual testing needed*
- [ ] Manual QA pass: token add/remove UX flow
- [ ] Manual QA pass: efficiency / API call count
- [ ] Clarify "Your PR" vs "Assigned" label logic

---

## v0.2 — Bug Fixes + Polish

**Goal:** Squash known bugs and add small UX improvements before building larger features.

### Bugs
- [ ] Draft PR CI indicator always shows "Checking mergeability" — should show actual CI status
- [ ] After owner re-requests review following "Changes requested", indicator should flip to orange (review requested), not stay red (changes requested)
- [ ] Draft PR can incorrectly show "Checks pending" when all checks have passed
- [ ] Draft PRs you didn't create and aren't assigned to should not appear in the app
- [ ] Failing CI checks info popup can show repeated entries

### UX improvements
- [ ] Sticky triage category headers: "NEEDS YOUR ACTION" / "WAITING ON OTHERS" / "YOUR DRAFT PRs" stay pinned as you scroll through their section (sticky-header style, each pushes the previous one up)
- [ ] CI checks info popup: show per-check status icon (green tick = passed, amber circle = running, red x = failed)

### Efficiency
- [ ] Skip polling draft PRs (or poll at a much lower frequency)

### UX / window
- [ ] **Resizable dropdown** — drag the bottom edge to resize the dropdown height; size persists across opens and app restarts

### Dev
- [ ] GitHub Actions CI: lint + style checks on push/PR

---

## v0.3 — Repo Management

**Goal:** Give users control over which repos are tracked and what's visible.

- [ ] **Subscribe / unsubscribe from repos** — user can add or remove repos from tracking entirely; unsubscribed repos are not fetched at all (UI: manage per-repo in Settings)
- [ ] **Filter repos** — dropdown filter in the main view so the user can select one or more repos and see only PRs from those repos

---

## v1.1 — Smarter Triage

**Goal:** Improve within-section PR ordering based on real-world usage data.

- [ ] **Urgency scoring** — replace `updated_at` sort with weighted urgency score. Gather data from 1–2 weeks of real use to determine weights (age, review state, CI state, etc.). Track which orderings feel wrong during personal use first.
- [ ] **Team review request support** — handle `requested_teams` from the GitHub API so CODEOWNERS/reviewer-team requests surface correctly as "waiting for review" or "review requested from me" instead of disappearing
- [ ] **Set / reorder PR priorities** — mark a PR as high priority to pin it to the top of its triage section; allow manual drag-to-reorder within sections

---

## v2 — Notifications + Collaboration

**Goal:** Rich notifications and light social/collaboration features.

### Architecture
- [ ] **Notification-driven hybrid polling** — replace pure polling with `/notifications` polling + targeted fetches for changed PRs. Dramatically reduces API calls for 50+ active PRs. Requires real-world API call data from v0.1/v1.x first.

### Notifications
- [ ] Configurable notification triggers — choose which status changes fire a notification (all PRs / assigned only / relevant only)
- [ ] Notify when tagged in a PR comment
- [ ] Notify when tagged in a PR review comment
- [ ] Unsubscribe from notifications for a specific PR
- [ ] Subscribe to notifications for a specific PR
- [ ] Notifications for GitHub issues (tagged, assigned, activity on assigned issue)

### Token management
- [ ] Guided token setup — walk user through selecting the right fine-grained token scopes during onboarding
- [ ] Token expiry reminder — user sets expiry date, app reminds them before it lapses
- [ ] Handle token scope conflicts when settings change

### Collaboration features
- [ ] Post review reminder comment — tag reviewers + custom message directly from the app
- [ ] Request a review from someone via the app
- [ ] Escalate a PR — post an `@user ESCALATE` comment; app surfaces escalated PRs prominently
- [ ] Merge mergeable PRs from within the app

### Quality of life
- [ ] Set working hours — suppress notifications outside working hours
- [ ] Catch-up view — summary of what happened while you were away
- [ ] Open worktree folder button per PR
