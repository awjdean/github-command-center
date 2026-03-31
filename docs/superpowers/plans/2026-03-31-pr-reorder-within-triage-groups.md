# PR Reorder Within Triage Groups — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users drag-and-drop PRs to reorder them within their triage sections (Needs Your Action, Waiting On Others, Your Draft PRs), with order persisted across app restarts and resilient to polling updates.

**Architecture:** A `PROrderStore` backed by `UserDefaults` stores custom ordering as arrays of PR IDs keyed by triage category. When order is applied or mutated, the store normalizes persisted IDs against the current live PR IDs, removes duplicates and stale IDs, and clears persistence entirely when the effective order matches the section's default sort. `AppState.recomputePRCaches()` is extended to apply stored order when available, falling back to default sorting for unordered or new PRs. `PRListView` uses SwiftUI's `onDrag` + `onDrop(of:delegate:)` with `DropDelegate` row targets plus a trailing end-of-section target because that API exposes the lifecycle hooks and `.move` proposal needed for precise reordering. The insertion indicator is required feedback; dragged-row dimming is optional and should only ship if transient drag state can be cleared reliably in manual testing.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14+, UserDefaults, UniformTypeIdentifiers, Swift Testing

**Design direction:** Utilitarian and minimal — matching the existing dark panel aesthetic. Drag handles appear only on hover. A thin blue insertion indicator gives precise placement feedback. A reset-order icon appears in the section header only when the effective persisted order differs from that section's default sort. If dragged-row dimming is added, it must clear reliably on cancelled drags; otherwise ship without it.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `GitHubCommandCenter/Services/PROrderStore.swift` | UserDefaults persistence for custom PR order per triage category |
| Modify | `GitHubCommandCenter/Models/AppState.swift` | Inject `PROrderStore`, use it in `recomputePRCaches()`, expose reorder/reset methods |
| Create | `GitHubCommandCenter/Views/PRReorderDropDelegate.swift` | Section-scoped drop delegate and trailing end-of-section drop target |
| Modify | `GitHubCommandCenter/Views/PRListView.swift` | Drag-and-drop wiring, drop indicator, section header reset button |
| Modify | `GitHubCommandCenter/Views/PRRowView.swift` | Add drag handle grip that appears on hover |
| Create | `GitHubCommandCenterTests/PROrderStoreTests.swift` | Unit tests for ordering persistence and merge logic |
| Create | `GitHubCommandCenterTests/AppStatePROrderTests.swift` | Integration tests: custom order applied to cached PR lists |

---

### Task 1: PROrderStore — Persistence Layer

**Files:**
- Create: `GitHubCommandCenter/Services/PROrderStore.swift`

- [ ] **Step 1: Write the failing test — storing and retrieving order**

Create `GitHubCommandCenterTests/PROrderStoreTests.swift`:

```swift
import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite
struct PROrderStoreTests {
    private func makeStore() -> PROrderStore {
        let defaults = UserDefaults(suiteName: "PROrderStoreTests.\(UUID().uuidString)")!
        return PROrderStore(defaults: defaults)
    }

    @Test
    func storedOrder_emptyByDefault() {
        let store = makeStore()
        #expect(store.storedOrder(for: .needsYourAction) == nil)
        #expect(store.storedOrder(for: .waitingOnOthers) == nil)
        #expect(store.storedOrder(for: .yourDraft) == nil)
    }

    @Test
    func setOrder_persistsAndRetrieves() {
        let store = makeStore()
        let ids = ["owner/repo#1", "owner/repo#3", "owner/repo#2"]
        store.setOrder(ids, for: .needsYourAction)
        #expect(store.storedOrder(for: .needsYourAction) == ids)
    }

    @Test
    func setOrder_categoriesAreIndependent() {
        let store = makeStore()
        store.setOrder(["a"], for: .needsYourAction)
        store.setOrder(["b"], for: .waitingOnOthers)
        #expect(store.storedOrder(for: .needsYourAction) == ["a"])
        #expect(store.storedOrder(for: .waitingOnOthers) == ["b"])
        #expect(store.storedOrder(for: .yourDraft) == nil)
    }

    @Test
    func clearOrder_removesStoredOrder() {
        let store = makeStore()
        store.setOrder(["a", "b"], for: .needsYourAction)
        store.clearOrder(for: .needsYourAction)
        #expect(store.storedOrder(for: .needsYourAction) == nil)
    }

    @Test
    func hasCustomOrder_reflectsStoredState() {
        let store = makeStore()
        #expect(store.hasCustomOrder(for: .needsYourAction) == false)
        store.setOrder(["a"], for: .needsYourAction)
        #expect(store.hasCustomOrder(for: .needsYourAction) == true)
        store.clearOrder(for: .needsYourAction)
        #expect(store.hasCustomOrder(for: .needsYourAction) == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test`
Expected: Compilation failure — `PROrderStore` does not exist.

- [ ] **Step 3: Implement PROrderStore**

Create `GitHubCommandCenter/Services/PROrderStore.swift`:

```swift
import Foundation

struct PROrderStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func storedOrder(for category: PRState.TriageCategory) -> [String]? {
        let key = defaultsKey(for: category)
        let stored = defaults.stringArray(forKey: key)
        if let stored, stored.isEmpty { return nil }
        return stored
    }

    func setOrder(_ ids: [String], for category: PRState.TriageCategory) {
        let key = defaultsKey(for: category)
        guard !ids.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(ids, forKey: key)
    }

    func clearOrder(for category: PRState.TriageCategory) {
        defaults.removeObject(forKey: defaultsKey(for: category))
    }

    func hasCustomOrder(for category: PRState.TriageCategory) -> Bool {
        storedOrder(for: category) != nil
    }

    private func defaultsKey(for category: PRState.TriageCategory) -> String {
        switch category {
        case .needsYourAction: return "prOrder.needsYourAction"
        case .waitingOnOthers: return "prOrder.waitingOnOthers"
        case .yourDraft: return "prOrder.yourDraft"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise run test`
Expected: All `PROrderStoreTests` pass.

- [ ] **Step 5: Commit**

```bash
git add GitHubCommandCenter/Services/PROrderStore.swift GitHubCommandCenterTests/PROrderStoreTests.swift
git commit -m "feat: add PROrderStore for persisting custom PR order per triage category"
```

---

### Task 2: PROrderStore — Merge Logic and Normalization Cleanup

**Files:**
- Modify: `GitHubCommandCenter/Services/PROrderStore.swift`
- Modify: `GitHubCommandCenterTests/PROrderStoreTests.swift`

- [ ] **Step 1: Write the failing test — applyOrder merges stored order with live PRs**

Add to `PROrderStoreTests.swift`:

```swift
@Test
func applyOrder_noStoredOrder_usesDefaultSort() {
    let store = makeStore()
    let prs = [
        PRState.fixture(number: 1, updatedAt: Date(timeIntervalSince1970: 100)),
        PRState.fixture(number: 2, updatedAt: Date(timeIntervalSince1970: 300)),
        PRState.fixture(number: 3, updatedAt: Date(timeIntervalSince1970: 200)),
    ]
    let sorted = store.applyOrder(
        to: prs,
        category: .waitingOnOthers,
        defaultSort: { $0.updatedAt > $1.updatedAt }
    )
    #expect(sorted.map(\.number) == [2, 3, 1])
}

@Test
func applyOrder_withStoredOrder_respectsCustomOrder() {
    let store = makeStore()
    let prs = [
        PRState.fixture(number: 1, repoFullName: "o/r"),
        PRState.fixture(number: 2, repoFullName: "o/r"),
        PRState.fixture(number: 3, repoFullName: "o/r"),
    ]
    store.setOrder(["o/r#3", "o/r#1", "o/r#2"], for: .needsYourAction)
    let sorted = store.applyOrder(
        to: prs,
        category: .needsYourAction,
        defaultSort: { $0.number < $1.number }
    )
    #expect(sorted.map(\.number) == [3, 1, 2])
}

@Test
func applyOrder_newPRsAppearAtEnd_inDefaultOrder() {
    let store = makeStore()
    let prs = [
        PRState.fixture(number: 1, repoFullName: "o/r", updatedAt: Date(timeIntervalSince1970: 100)),
        PRState.fixture(number: 2, repoFullName: "o/r", updatedAt: Date(timeIntervalSince1970: 300)),
        PRState.fixture(number: 3, repoFullName: "o/r", updatedAt: Date(timeIntervalSince1970: 200)),
    ]
    // Only PR 1 is in stored order — PRs 2 and 3 are "new"
    store.setOrder(["o/r#1"], for: .waitingOnOthers)
    let sorted = store.applyOrder(
        to: prs,
        category: .waitingOnOthers,
        defaultSort: { $0.updatedAt > $1.updatedAt }
    )
    // PR 1 first (stored), then 2, 3 in default sort (by updatedAt desc)
    #expect(sorted.map(\.number) == [1, 2, 3])
    #expect(store.storedOrder(for: .waitingOnOthers) == ["o/r#1", "o/r#2", "o/r#3"])
}

@Test
func applyOrder_removedPRs_areIgnoredAndStorageFallsBackToDefault() {
    let store = makeStore()
    let prs = [
        PRState.fixture(number: 2, repoFullName: "o/r"),
    ]
    // PR 1 and 3 were in stored order but no longer exist
    store.setOrder(["o/r#1", "o/r#2", "o/r#3"], for: .needsYourAction)
    let sorted = store.applyOrder(
        to: prs,
        category: .needsYourAction,
        defaultSort: { $0.number < $1.number }
    )
    #expect(sorted.map(\.number) == [2])
    #expect(store.storedOrder(for: .needsYourAction) == nil)
}

@Test
func applyOrder_duplicateStoredIDs_areDeduplicatedAndPersisted() {
    let store = makeStore()
    let prs = [
        PRState.fixture(number: 1, repoFullName: "o/r"),
        PRState.fixture(number: 2, repoFullName: "o/r"),
        PRState.fixture(number: 3, repoFullName: "o/r"),
    ]
    store.setOrder(["o/r#3", "o/r#1", "o/r#3"], for: .needsYourAction)

    let sorted = store.applyOrder(
        to: prs,
        category: .needsYourAction,
        defaultSort: { $0.number < $1.number }
    )

    #expect(sorted.map(\.number) == [3, 1, 2])
    #expect(store.storedOrder(for: .needsYourAction) == ["o/r#3", "o/r#1", "o/r#2"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test`
Expected: Compilation failure — `applyOrder(to:category:defaultSort:)` does not exist.

- [ ] **Step 3: Implement applyOrder**

Add to `PROrderStore.swift`:

```swift
private func normalizedOrderIDs(
    for category: PRState.TriageCategory,
    currentIDs: [String]
) -> (ids: [String], hadStoredOrder: Bool, didNormalize: Bool) {
    let storedIDs = storedOrder(for: category)
    let rawStoredIDs = storedIDs ?? []
    let liveIDs = Set(currentIDs)
    var normalized: [String] = []
    var seen = Set<String>()

    for id in rawStoredIDs where liveIDs.contains(id) {
        if seen.insert(id).inserted {
            normalized.append(id)
        }
    }

    for id in currentIDs where seen.insert(id).inserted {
        normalized.append(id)
    }

    return (
        ids: normalized,
        hadStoredOrder: storedIDs != nil,
        didNormalize: normalized != rawStoredIDs
    )
}

private func persistCustomOrder(
    _ ids: [String],
    defaultIDs: [String],
    for category: PRState.TriageCategory
) {
    if ids == defaultIDs {
        clearOrder(for: category)
    } else {
        setOrder(ids, for: category)
    }
}

func applyOrder(
    to prs: [PRState],
    category: PRState.TriageCategory,
    defaultSort: (PRState, PRState) -> Bool
) -> [PRState] {
    let defaultSortedPRs = prs.sorted(by: defaultSort)
    let defaultIDs = defaultSortedPRs.map(\.id)
    let prsByID = Dictionary(uniqueKeysWithValues: defaultSortedPRs.map { ($0.id, $0) })
    let normalization = normalizedOrderIDs(
        for: category,
        currentIDs: defaultIDs
    )
    if normalization.hadStoredOrder && normalization.didNormalize {
        persistCustomOrder(normalization.ids, defaultIDs: defaultIDs, for: category)
    }
    return normalization.ids.compactMap { prsByID[$0] }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise run test`
Expected: All `PROrderStoreTests` pass.

- [ ] **Step 5: Commit**

```bash
git add GitHubCommandCenter/Services/PROrderStore.swift GitHubCommandCenterTests/PROrderStoreTests.swift
git commit -m "feat: add applyOrder to merge custom order with live PR data"
```

---

### Task 3: PROrderStore — moveItem Helper

**Files:**
- Modify: `GitHubCommandCenter/Services/PROrderStore.swift`
- Modify: `GitHubCommandCenterTests/PROrderStoreTests.swift`

- [ ] **Step 1: Write the failing test — moveItem reorders within stored order**

Add to `PROrderStoreTests.swift`:

```swift
@Test
func moveItem_movesToBeforeTarget() {
    let store = makeStore()
    store.setOrder(["a", "b", "c", "d"], for: .needsYourAction)
    store.moveItem("d", before: "b", using: ["a", "b", "c", "d"], for: .needsYourAction)
    #expect(store.storedOrder(for: .needsYourAction) == ["a", "d", "b", "c"])
}

@Test
func moveItem_movesToEnd_whenBeforeIDIsNil() {
    let store = makeStore()
    store.setOrder(["a", "b", "c"], for: .needsYourAction)
    store.moveItem("a", before: nil, using: ["a", "b", "c"], for: .needsYourAction)
    #expect(store.storedOrder(for: .needsYourAction) == ["b", "c", "a"])
}

@Test
func moveItem_noStoredOrder_createsFromCurrentList() {
    let store = makeStore()
    store.moveItem("c", before: "a", using: ["a", "b", "c"], for: .waitingOnOthers)
    #expect(store.storedOrder(for: .waitingOnOthers) == ["c", "a", "b"])
}

@Test
func moveItem_partialStoredOrder_canMoveNewlyPolledPR() {
    let store = makeStore()
    store.setOrder(["a"], for: .needsYourAction)
    store.moveItem("c", before: "a", using: ["a", "b", "c"], for: .needsYourAction)
    #expect(store.storedOrder(for: .needsYourAction) == ["c", "a", "b"])
}

@Test
func moveItem_sameEffectivePosition_keepsCustomOrder() {
    let store = makeStore()
    store.setOrder(["c", "a", "b"], for: .needsYourAction)
    store.moveItem("a", before: "b", using: ["a", "b", "c"], for: .needsYourAction)
    #expect(store.storedOrder(for: .needsYourAction) == ["c", "a", "b"])
}

@Test
func moveItem_resultMatchingDefaultOrder_clearsStoredOrder() {
    let store = makeStore()
    store.setOrder(["c", "a", "b"], for: .needsYourAction)
    store.moveItem("c", before: nil, using: ["a", "b", "c"], for: .needsYourAction)
    #expect(store.storedOrder(for: .needsYourAction) == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test`
Expected: Compilation failure — `moveItem` does not exist.

- [ ] **Step 3: Implement moveItem**

Add to `PROrderStore.swift`:

```swift
func moveItem(
    _ movedID: String,
    before targetID: String?,
    using currentIDs: [String],
    for category: PRState.TriageCategory
) {
    var order = normalizedOrderIDs(for: category, currentIDs: currentIDs).ids
    guard let fromIndex = order.firstIndex(of: movedID) else { return }
    order.remove(at: fromIndex)

    if let targetID, let toIndex = order.firstIndex(of: targetID) {
        order.insert(movedID, at: toIndex)
    } else {
        order.append(movedID)
    }

    persistCustomOrder(order, defaultIDs: currentIDs, for: category)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise run test`
Expected: All `PROrderStoreTests` pass.

- [ ] **Step 5: Commit**

```bash
git add GitHubCommandCenter/Services/PROrderStore.swift GitHubCommandCenterTests/PROrderStoreTests.swift
git commit -m "feat: add moveItem to PROrderStore for drag-and-drop reordering"
```

---

### Task 4: AppState Integration — Apply Custom Ordering

**Files:**
- Modify: `GitHubCommandCenter/Models/AppState.swift`

- [ ] **Step 1: Write the failing test — AppState applies custom order to cached PRs**

Create `GitHubCommandCenterTests/AppStatePROrderTests.swift`:

```swift
import Foundation
import Testing

@testable import GitHubCommandCenter

@MainActor
@Suite
struct AppStatePROrderTests {
    private func makeAppState(orderStore: PROrderStore? = nil) -> AppState {
        AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {},
            orderStore: orderStore ?? PROrderStore(defaults: UserDefaults(suiteName: "AppStatePROrderTests.\(UUID().uuidString)")!)
        )
    }

    @Test
    func needsActionPRs_withCustomOrder_respectsStoredOrder() {
        let defaults = UserDefaults(suiteName: "AppStatePROrderTests.\(UUID().uuidString)")!
        let store = PROrderStore(defaults: defaults)

        // Store custom order: PR 3 first, then PR 1
        store.setOrder(["o/r#3", "o/r#1"], for: .needsYourAction)

        let appState = makeAppState(orderStore: store)
        appState.prs = [
            PRState.fixture(number: 1, repoFullName: "o/r", reviewRequestedFromMe: true),
            PRState.fixture(number: 3, repoFullName: "o/r", reviewRequestedFromMe: true),
        ]

        #expect(appState.needsActionPRs.map(\.number) == [3, 1])
    }

    @Test
    func reorderPR_withPartialStoredOrder_canMoveNewlyPolledPR() {
        let defaults = UserDefaults(suiteName: "AppStatePROrderTests.\(UUID().uuidString)")!
        let store = PROrderStore(defaults: defaults)
        store.setOrder(["o/r#1"], for: .needsYourAction)

        let appState = makeAppState(orderStore: store)
        appState.prs = [
            PRState.fixture(number: 1, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 300)),
            PRState.fixture(number: 2, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 200)),
            PRState.fixture(number: 3, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 100)),
        ]

        #expect(appState.needsActionPRs.map(\.number) == [1, 2, 3])

        appState.reorderPR(movedID: "o/r#3", beforeID: "o/r#1", inCategory: .needsYourAction)

        #expect(appState.needsActionPRs.map(\.number) == [3, 1, 2])
    }

    @Test
    func reorderPR_updatesOrderAndCaches() {
        let appState = makeAppState()
        appState.prs = [
            PRState.fixture(number: 1, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 300)),
            PRState.fixture(number: 2, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 200)),
            PRState.fixture(number: 3, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 100)),
        ]

        // Default order by urgency/date: 1, 2, 3
        #expect(appState.needsActionPRs.map(\.number) == [1, 2, 3])

        // Move PR 3 before PR 1
        appState.reorderPR(movedID: "o/r#3", beforeID: "o/r#1", inCategory: .needsYourAction)

        #expect(appState.needsActionPRs.map(\.number) == [3, 1, 2])
    }

    @Test
    func resetOrder_restoresDefaultSort() {
        let appState = makeAppState()
        appState.prs = [
            PRState.fixture(number: 1, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 300)),
            PRState.fixture(number: 2, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 100)),
        ]

        appState.reorderPR(movedID: "o/r#2", beforeID: "o/r#1", inCategory: .needsYourAction)
        #expect(appState.needsActionPRs.map(\.number) == [2, 1])

        appState.resetOrder(for: .needsYourAction)
        #expect(appState.needsActionPRs.map(\.number) == [1, 2])
    }

    @Test
    func hasCustomOrder_reflectsStoreState() {
        let appState = makeAppState()
        #expect(appState.hasCustomOrder(for: .needsYourAction) == false)

        appState.prs = [
            PRState.fixture(number: 1, repoFullName: "o/r", reviewRequestedFromMe: true),
            PRState.fixture(number: 2, repoFullName: "o/r", reviewRequestedFromMe: true),
        ]

        appState.reorderPR(movedID: "o/r#2", beforeID: "o/r#1", inCategory: .needsYourAction)
        #expect(appState.hasCustomOrder(for: .needsYourAction) == true)
    }

    @Test
    func hasCustomOrder_returnsFalseWhenReorderReturnsToDefaultSort() {
        let appState = makeAppState()
        appState.prs = [
            PRState.fixture(number: 1, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 300)),
            PRState.fixture(number: 2, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 200)),
            PRState.fixture(number: 3, repoFullName: "o/r", reviewRequestedFromMe: true,
                            updatedAt: Date(timeIntervalSince1970: 100)),
        ]

        appState.reorderPR(movedID: "o/r#3", beforeID: "o/r#1", inCategory: .needsYourAction)
        #expect(appState.hasCustomOrder(for: .needsYourAction) == true)

        appState.reorderPR(movedID: "o/r#3", beforeID: nil, inCategory: .needsYourAction)
        #expect(appState.needsActionPRs.map(\.number) == [1, 2, 3])
        #expect(appState.hasCustomOrder(for: .needsYourAction) == false)
    }

    private final class StubPollingEngine: PollingControlling {
        func start() {}
        func stop() {}
        func reset() {}
        func forceRefresh() {}
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test`
Expected: Compilation failure — `AppState` init doesn't accept `orderStore`, no `reorderPR`/`resetOrder`/`hasCustomOrder` methods.

- [ ] **Step 3: Modify AppState to accept and use PROrderStore**

In `GitHubCommandCenter/Models/AppState.swift`, make these changes:

**Add `orderStore` property and update initializers** (after the existing `private var cached...` lines, around line 127):

Replace the private stored properties section:

```swift
    private let makePollingEngine: (AppState) -> any PollingControlling
    private let requestNotificationPermission: () async -> Void
    private let preloadTokenIfNeeded: () -> Void
    private var cachedNeedsActionPRs: [PRState] = []
    private var cachedWaitingOnOthersPRs: [PRState] = []
    private var cachedYourDraftPRs: [PRState] = []
```

with:

```swift
    private let makePollingEngine: (AppState) -> any PollingControlling
    private let requestNotificationPermission: () async -> Void
    private let preloadTokenIfNeeded: () -> Void
    private var orderStore: PROrderStore
    private var cachedNeedsActionPRs: [PRState] = []
    private var cachedWaitingOnOthersPRs: [PRState] = []
    private var cachedYourDraftPRs: [PRState] = []
```

**Update the default init** (around line 129):

Replace:

```swift
    init() {
        self.makePollingEngine = { PollingEngine(appState: $0) }
        self.requestNotificationPermission = { await NotificationService.shared.requestPermission() }
        self.preloadTokenIfNeeded = {
            _ = EnvironmentTokenBootstrapper().preloadIfNeeded()
        }
    }
```

with:

```swift
    init() {
        self.makePollingEngine = { PollingEngine(appState: $0) }
        self.requestNotificationPermission = { await NotificationService.shared.requestPermission() }
        self.preloadTokenIfNeeded = {
            _ = EnvironmentTokenBootstrapper().preloadIfNeeded()
        }
        self.orderStore = PROrderStore()
    }
```

**Update the test-friendly init** (around line 137):

Replace:

```swift
    init(
        makePollingEngine: @escaping (AppState) -> any PollingControlling,
        requestNotificationPermission: @escaping () async -> Void,
        preloadTokenIfNeeded: @escaping () -> Void = {}
    ) {
        self.makePollingEngine = makePollingEngine
        self.requestNotificationPermission = requestNotificationPermission
        self.preloadTokenIfNeeded = preloadTokenIfNeeded
    }
```

with:

```swift
    init(
        makePollingEngine: @escaping (AppState) -> any PollingControlling,
        requestNotificationPermission: @escaping () async -> Void,
        preloadTokenIfNeeded: @escaping () -> Void = {},
        orderStore: PROrderStore = PROrderStore()
    ) {
        self.makePollingEngine = makePollingEngine
        self.requestNotificationPermission = requestNotificationPermission
        self.preloadTokenIfNeeded = preloadTokenIfNeeded
        self.orderStore = orderStore
    }
```

**Update `recomputePRCaches`** (around line 157):

Replace:

```swift
    private func recomputePRCaches() {
        cachedNeedsActionPRs =
            prs
            .filter { $0.triageCategory == .needsYourAction }
            .sorted(by: PRState.compareForNeedsAction)
        cachedWaitingOnOthersPRs =
            prs
            .filter { $0.triageCategory == .waitingOnOthers }
            .sorted { $0.updatedAt > $1.updatedAt }
        cachedYourDraftPRs =
            prs
            .filter { $0.triageCategory == .yourDraft }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
```

with:

```swift
    private func recomputePRCaches() {
        cachedNeedsActionPRs = orderStore.applyOrder(
            to: prs.filter { $0.triageCategory == .needsYourAction },
            category: .needsYourAction,
            defaultSort: PRState.compareForNeedsAction
        )
        cachedWaitingOnOthersPRs = orderStore.applyOrder(
            to: prs.filter { $0.triageCategory == .waitingOnOthers },
            category: .waitingOnOthers,
            defaultSort: { $0.updatedAt > $1.updatedAt }
        )
        cachedYourDraftPRs = orderStore.applyOrder(
            to: prs.filter { $0.triageCategory == .yourDraft },
            category: .yourDraft,
            defaultSort: { $0.updatedAt > $1.updatedAt }
        )
    }
```

**Add reorder and reset methods** (after `recomputePRCaches`, before `startPollingIfNeeded`):

```swift
    func reorderPR(movedID: String, beforeID: String?, inCategory category: PRState.TriageCategory) {
        let currentIDs: [String]
        switch category {
        case .needsYourAction: currentIDs = cachedNeedsActionPRs.map(\.id)
        case .waitingOnOthers: currentIDs = cachedWaitingOnOthersPRs.map(\.id)
        case .yourDraft: currentIDs = cachedYourDraftPRs.map(\.id)
        }
        orderStore.moveItem(movedID, before: beforeID, using: currentIDs, for: category)
        objectWillChange.send()
        recomputePRCaches()
    }

    func resetOrder(for category: PRState.TriageCategory) {
        orderStore.clearOrder(for: category)
        objectWillChange.send()
        recomputePRCaches()
    }

    func hasCustomOrder(for category: PRState.TriageCategory) -> Bool {
        orderStore.hasCustomOrder(for: category)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise run test`
Expected: All tests pass, including new `AppStatePROrderTests`.

- [ ] **Step 5: Commit**

```bash
git add GitHubCommandCenter/Models/AppState.swift GitHubCommandCenterTests/AppStatePROrderTests.swift
git commit -m "feat: integrate PROrderStore into AppState for custom PR ordering"
```

---

### Task 5: PRListView — Drop Delegate and Drag Wiring

**Files:**
- Create: `GitHubCommandCenter/Views/PRReorderDropDelegate.swift`
- Modify: `GitHubCommandCenter/Views/PRListView.swift`

- [ ] **Step 1: Re-read the SwiftUI docs, then create PRReorderDropDelegate**

Before implementing, read the Apple SwiftUI docs via Context7 for:
- `View.onDrop(of:delegate:)`
- `DropDelegate`
- `View.draggable(_:)`
- `View.dropDestination(...)`

Implementation note: use `onDrop(of:delegate:)` here, not `dropDestination`, because row-by-row reordering needs `DropDelegate` lifecycle callbacks (`validateDrop`, `dropEntered`, `dropExited`, `dropUpdated`, `performDrop`) plus `DropProposal(operation: .move)` for precise insertion behavior.

Create `GitHubCommandCenter/Views/PRReorderDropDelegate.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

enum PRDropTarget: Equatable {
    case before(String)
    case endOfSection(PRState.TriageCategory)
}

struct PRReorderDropDelegate: DropDelegate {
    let target: PRDropTarget
    let category: PRState.TriageCategory
    @Binding var draggedPRID: String?
    @Binding var draggedPRCategory: PRState.TriageCategory?
    @Binding var dropTarget: PRDropTarget?
    let onReorder: (String, String?, PRState.TriageCategory) -> Void
    let clearDragState: () -> Void

    func dropEntered(info: DropInfo) {
        guard isValidDrop else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            dropTarget = target
        }
    }

    func dropExited(info: DropInfo) {
        if dropTarget == target {
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTarget = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isValidDrop, let draggedID = draggedPRID else { return false }

        let beforeID: String?
        switch target {
        case .before(let id):
            beforeID = id
        case .endOfSection:
            beforeID = nil
        }

        onReorder(draggedID, beforeID, category)
        clearDragState()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isValidDrop ? DropProposal(operation: .move) : nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        isValidDrop
    }

    private var isValidDrop: Bool {
        guard let draggedID = draggedPRID, draggedPRCategory == category else { return false }

        switch target {
        case .before(let id):
            return draggedID != id
        case .endOfSection:
            return true
        }
    }
}
```

- [ ] **Step 2: Run `mise run build` to verify it compiles**

Expected: Build succeeds.

- [ ] **Step 3: Add drag state and update prSections in PRListView**

In `GitHubCommandCenter/Views/PRListView.swift`, add state properties to `PRListView` (after the existing `@State private var panelMode` line):

```swift
    @State private var draggedPRID: String?
    @State private var draggedPRCategory: PRState.TriageCategory?
    @State private var dropTarget: PRDropTarget?
```

Add `import UniformTypeIdentifiers` at the top of the file (after `import SwiftUI`).

Replace the `prSections` computed property (lines 182–211):

```swift
    @ViewBuilder
    private var prSections: some View {
        let needsAction = appState.needsActionPRs
        let waiting = appState.waitingOnOthersPRs
        let drafts = appState.yourDraftPRs

        if !needsAction.isEmpty {
            sectionHeader("NEEDS YOUR ACTION", category: .needsYourAction)
            draggableSection(prs: needsAction, category: .needsYourAction, opacity: 1.0)
        }

        if !waiting.isEmpty {
            sectionHeader("WAITING ON OTHERS", category: .waitingOnOthers)
            draggableSection(prs: waiting, category: .waitingOnOthers, opacity: 0.55)
        }

        if !drafts.isEmpty {
            sectionHeader("YOUR DRAFT PRs", category: .yourDraft)
            draggableSection(prs: drafts, category: .yourDraft, opacity: 0.5)
        }
    }

    private func draggableSection(prs: [PRState], category: PRState.TriageCategory, opacity: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(prs) { pr in
                VStack(spacing: 0) {
                    if dropTarget == .before(pr.id) {
                        dropIndicator()
                    }
                    PRRowView(pr: pr)
                        .opacity(opacity)
                        .onDrag {
                            draggedPRID = pr.id
                            draggedPRCategory = category
                            dropTarget = nil
                            return NSItemProvider(object: pr.id as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PRReorderDropDelegate(
                                target: .before(pr.id),
                                category: category,
                                draggedPRID: $draggedPRID,
                                draggedPRCategory: $draggedPRCategory,
                                dropTarget: $dropTarget,
                                onReorder: { movedID, beforeID, cat in
                                    appState.reorderPR(movedID: movedID, beforeID: beforeID, inCategory: cat)
                                },
                                clearDragState: clearDragState
                            )
                        )
                    themedDivider()
                }
            }

            if dropTarget == .endOfSection(category) {
                dropIndicator()
            }

            Color.clear
                .frame(height: 20)
                .contentShape(Rectangle())
                .onDrop(
                    of: [UTType.text],
                    delegate: PRReorderDropDelegate(
                        target: .endOfSection(category),
                        category: category,
                        draggedPRID: $draggedPRID,
                        draggedPRCategory: $draggedPRCategory,
                        dropTarget: $dropTarget,
                        onReorder: { movedID, beforeID, cat in
                            appState.reorderPR(movedID: movedID, beforeID: beforeID, inCategory: cat)
                        },
                        clearDragState: clearDragState
                    )
                )
        }
    }

    private func clearDragState() {
        draggedPRID = nil
        draggedPRCategory = nil
        dropTarget = nil
    }

    private func dropIndicator() -> some View {
        Rectangle()
            .fill(Color.linkBlue)
            .frame(height: 2)
            .padding(.horizontal, Spacing.xl)
            .transition(.opacity)
    }
```

Important implementation note:
- Do not add dragged-row dimming in the first pass.
- The insertion indicator is the required feedback.
- After the smoke test, only add source-row dimming if it can be cleared reliably on cancelled drags. If it can stick, remove it and keep the insertion indicator only.

- [ ] **Step 4: Update sectionHeader to accept category and show reset button**

Replace the existing `sectionHeader` function (lines 213–222):

```swift
    private func sectionHeader(_ title: String, category: PRState.TriageCategory) -> some View {
        HStack {
            Text(title)
                .font(.sectionLabel)
                .tracking(1)
                .foregroundColor(.textMuted)
            Spacer()
            if appState.hasCustomOrder(for: category) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.resetOrder(for: category)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
                .help("Reset to default order")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
```

Also remove the old `sectionHeader` overload that only takes a `String`, and update the "RECENTLY CLOSED" call site (around line 166) to use a plain version:

```swift
    // Replace the old sectionHeader("RECENTLY CLOSED") call with inline styling:
    if !appState.recentlyClosedPRs.isEmpty {
        Text("RECENTLY CLOSED")
            .font(.sectionLabel)
            .tracking(1)
            .foregroundColor(.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
        ForEach(appState.recentlyClosedPRs) { pr in
            PRRowView(pr: pr).opacity(0.5)
            themedDivider()
        }
    }
```

- [ ] **Step 5: Run `mise run build` to verify it compiles**

Expected: Build succeeds.

- [ ] **Step 6: Run `mise run test` to verify nothing is broken**

Expected: All tests pass.

- [ ] **Step 7: Run a manual drag-and-drop smoke test**

Run: `mise run start`

Expected:
- Dragging within a section shows the insertion indicator only in that same section.
- Dropping below the last row in a section moves the PR to the end of that section.
- Dragging over a different triage section shows no active drop indicator and does not reorder.
- Cancelling a drag or leaving valid drop targets clears all transient reorder UI.
- If optional source-row dimming is attempted and cannot be cleared reliably, remove it before merging.

- [ ] **Step 8: Commit**

```bash
git add GitHubCommandCenter/Views/PRReorderDropDelegate.swift GitHubCommandCenter/Views/PRListView.swift
git commit -m "feat: add drag-and-drop PR reordering with drop indicator and section reset"
```

---

### Task 6: PRRowView — Drag Handle on Hover

**Files:**
- Modify: `GitHubCommandCenter/Views/PRRowView.swift`

- [ ] **Step 1: Add a drag handle grip that appears on hover**

In `GitHubCommandCenter/Views/PRRowView.swift`, add a grip icon to the left of the row content. Modify the `body` property.

Replace the outer `HStack` (the current body content, lines 13–85):

```swift
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundColor(.textMuted)
                .opacity(isHovered ? 0.7 : 0)
                .frame(width: 10)
                .animation(.easeInOut(duration: 0.15), value: isHovered)

            VStack(alignment: .leading, spacing: Spacing.hairline * 2) {
                HStack(spacing: Spacing.xs) {
                    Button {
                        openPullRequest()
                    } label: {
                        Text("#\(pr.number)")
                            .font(.prNumber)
                            .foregroundColor(.linkBlue)
                            .underline()
                    }
                    .buttonStyle(.plain)

                    if !pr.displayRole.isEmpty {
                        Text(pr.displayRole)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(Color.panelSurface)
                            .cornerRadius(Spacing.xxxs)
                    }

                    Spacer()

                    if pr.draftStatus == .draft {
                        Text("DRAFT")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.textMuted)
                            .padding(.horizontal, Spacing.xxxs)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.xxxs)
                                    .stroke(Color.textMuted.opacity(0.5), lineWidth: 0.5)
                            )
                    }
                }

                Text(pr.title)
                    .font(.prTitle)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: Spacing.xs) {
                    Text(pr.repoFullName)
                        .font(.prRepo)
                        .foregroundColor(.textMuted)

                    Spacer()

                    HStack(spacing: 5) {
                        StatusDotView(dimension: .ci, pr: pr)
                        StatusDotView(dimension: .review, pr: pr)
                        StatusDotView(dimension: .merge, pr: pr)
                    }
                }
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(isHovered ? Color.panelSurface : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .accessibilityLabel(PRRowPresentation.accessibilityLabel(for: pr))
        .alert("Unable to Open Pull Request", isPresented: $isShowingOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openErrorMessage)
        }
    }
```

Key changes:
- Added `Image(systemName: "line.3.horizontal")` grip icon that fades in on hover
- Changed `.padding(.horizontal, Spacing.xl)` to `.padding(.leading, Spacing.lg)` + `.padding(.trailing, Spacing.xl)` so the grip aligns closer to the left edge

- [ ] **Step 2: Run `mise run build` to verify it compiles**

Expected: Build succeeds.

- [ ] **Step 3: Run `mise run test` to verify nothing is broken**

Expected: All tests pass. (Existing `PRRowPresentationTests` should still pass since we only changed layout, not presentation logic.)

- [ ] **Step 4: Commit**

```bash
git add GitHubCommandCenter/Views/PRRowView.swift
git commit -m "feat: add drag handle grip icon that appears on PR row hover"
```

---

### Task 7: Style Check and Final Verification

**Files:** All modified files

- [ ] **Step 1: Run style checks**

Run: `mise run check`
Expected: No style violations.

- [ ] **Step 2: Run full verification**

Run: `mise run verify`
Expected: Auto-fixes, style checks, and tests all pass.

- [ ] **Step 3: Run persistence and polling smoke checks**

Run: `mise run start`

Expected:
- Reordering a PR within a populated triage section persists after closing and reopening the app.
- Reordering a newly appeared PR still works when a partial custom order already exists for that section.
- Triggering a refresh keeps the custom order for existing PRs while appending new PRs in default order.

- [ ] **Step 4: Fix any issues found**

If style or test issues arise, fix them and re-run `mise run verify`.

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address style check issues in PR reorder implementation"
```
