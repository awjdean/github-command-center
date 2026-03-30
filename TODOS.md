# TODOS

## V2 — Notification-driven hybrid polling
Replace pure polling with a hybrid: poll `/notifications` cheaply, then fetch full
details only for changed PRs. Dramatically reduces API calls for 50+ active PRs.
Current MVP uses 60s polling with ETag caching, which works for <100 PRs. The
notification API has its own quirks (different auth, threading model). Depends on
MVP shipping and real-world API call data.

## V1.1 — Urgency scoring with real-world weights
After 1-2 weeks of using updated_at sort in MVP, add urgency scoring with weights
informed by actual usage. The triage split (Needs Action vs Waiting) ships in MVP.
Only the within-section sort order is deferred. Track which PR orderings feel wrong
during personal use, then define weights based on those observations.
