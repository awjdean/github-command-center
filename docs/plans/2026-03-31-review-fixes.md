# Review Findings Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify each cited review finding against the current checkout and fix only the issues that still apply.

**Architecture:** Keep changes local to the affected workflow, services, views, tests, and docs. Add focused regression coverage for behavior changes first, then implement the minimal production changes needed to make those tests pass.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, GitHub Actions, `mise`

### Task 1: Verify Findings and Capture Red Tests

**Files:**
- Modify: `GitHubCommandCenterTests/GitHubRESTClientTests.swift`
- Modify: `GitHubCommandCenterTests/GitHubRESTClientTokenAccessTests.swift`
- Modify: `GitHubCommandCenterTests/AppStateTests.swift`
- Modify: `GitHubCommandCenterTests/NotificationServiceTests.swift`
- Modify: `GitHubCommandCenterTests/SettingsValidationTests.swift`

**Step 1: Write failing tests for remaining behavior changes**

- Add a cache-eviction test proving GitHub REST caching preserves recently used entries instead of clearing the full cache.
- Add an app-state/UI guard test proving recently closed PRs are only shown for successful load states.
- Add a notification scheduling test proving delivery errors are surfaced to an injected handler.
- Relax the settings validation assertion so it checks the stable part of the keychain error.
- Add the missing page-11 pagination stub in the token-access limit test.

**Step 2: Run targeted tests to verify they fail for the expected reason**

Run:

```bash
xcodebuild test -project GitHubCommandCenter.xcodeproj -scheme GitHubCommandCenter -destination 'platform=macOS' -only-testing:GitHubCommandCenterTests/GitHubRESTClientTests -only-testing:GitHubCommandCenterTests/NotificationServiceTests -only-testing:GitHubCommandCenterTests/AppStateTests -only-testing:GitHubCommandCenterTests/SettingsValidationTests
```

Expected: failures around cache eviction, notification delivery error handling, and the recently-closed visibility helper until implementation lands.

### Task 2: Implement the Minimal Fixes

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `GitHubCommandCenter/Services/GitHubRESTClient.swift`
- Modify: `GitHubCommandCenter/Services/KeychainService.swift`
- Modify: `GitHubCommandCenter/Services/NotificationService.swift`
- Modify: `GitHubCommandCenter/Views/PRListView.swift`
- Create: `GitHubCommandCenter/Logging.swift`
- Modify: `GitHubCommandCenter/Views/PRRowView.swift`
- Modify: `GitHubCommandCenter/Views/SettingsView.swift`
- Modify: `GitHubCommandCenterTests/GitHubRESTClientTestSupport.swift`
- Modify: `GitHubCommandCenterTests/Helpers/MockGitHubDataSource.swift`
- Modify: `TESTING_GUIDE.md`
- Modify: `mise.toml`

**Step 1: Replace the broad Xcode action tag with a pinned release**

- Update `maxim-lobanov/setup-xcode@v1` to a specific tested `v1.x.y` tag in `release.yml`.

**Step 2: Replace whole-cache clearing with LRU eviction**

- Store response data and ETags together in one LRU entry.
- Touch entries on read and write.
- Evict oldest entries until the cache is back under `maxCacheEntries`.

**Step 3: Harden token storage and notification delivery**

- Add `kSecAttrAccessible` to the shared keychain query.
- Route notification scheduling through `add(_:withCompletionHandler:)` and surface delivery errors via logging/test injection.

**Step 4: Apply the smaller correctness fixes**

- Gate recently closed rendering on successful load states only.
- Move the logging subsystem constant out of `Theme.swift`.
- Add explicit `Harness.teardown()` cleanup and call it deterministically in REST client tests.
- Synchronize all mock data-source mutable state behind one queue.
- Update docs and `mise` task metadata.

### Task 3: Verify and Summarize

**Files:**
- Verify only

**Step 1: Run targeted tests and focused repo checks**

Run:

```bash
mise run check-style
xcodebuild test -project GitHubCommandCenter.xcodeproj -scheme GitHubCommandCenter -destination 'platform=macOS' -only-testing:GitHubCommandCenterTests/GitHubRESTClientTests -only-testing:GitHubCommandCenterTests/GitHubRESTClientTokenAccessTests -only-testing:GitHubCommandCenterTests/GitHubRESTClientValidationTests -only-testing:GitHubCommandCenterTests/AppStateTests -only-testing:GitHubCommandCenterTests/PollingEngineTests -only-testing:GitHubCommandCenterTests/NotificationServiceTests -only-testing:GitHubCommandCenterTests/SettingsValidationTests -only-testing:GitHubCommandCenterTests/KeychainServiceTests
```

Expected: targeted tests pass, style checks pass, and remaining changed files are the intended review-fix edits.
