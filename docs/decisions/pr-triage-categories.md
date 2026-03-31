# PR Triage Categories

PRs are sorted into three sections in the panel, from top to bottom: **Needs Your Action**, **Waiting on Others**, and **Your Draft PRs**.

## Your Draft PRs

Any PR with `draftStatus == .draft` where you created it or are assigned to it. Draft PRs from others that you didn't create and aren't assigned to fall through to Waiting on Others instead.

## Needs Your Action

A non-draft PR lands here if **any** of the following are true:

- **You've been asked to review it** (`reviewRequestedFromMe`)
- **You're assigned to it** (`assignedToMe`)
- **You created it** and at least one of these signals is present:
  - CI is failing
  - There are merge conflicts
  - Changes have been requested by a reviewer
  - It's approved **and** merge-ready (clean merge status) -- i.e. you can go merge it now

## Waiting on Others

Everything else. This covers:

- PRs you created that are in a healthy state (CI passing, no conflicts, reviews pending or not yet requested)
- Draft PRs from other people that you're not assigned to
- Any PR where you have no ownership role and haven't been asked to act

## Sort order

- **Needs Your Action** is sorted by urgency score (descending), then by most recently updated. The urgency score weights: CI failures on your PRs (+3), changes requested on your PRs (+3), merge conflicts (+2), review requested from you (+2), assigned to you (+1), approved and merge-ready (+1).
- **Waiting on Others** and **Your Draft PRs** are sorted by most recently updated.

## Implementation

The triage logic lives in `PRState.triageCategory` (`GitHubCommandCenter/Models/PRState.swift`). The urgency score is computed by `PRState.urgencyScore` in the same file. `AppState` caches the filtered/sorted lists and exposes them as `needsActionPRs`, `waitingOnOthersPRs`, and `yourDraftPRs`.
