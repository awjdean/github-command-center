We want to build a macOS menu bar app, which provides a quick view of the status of our GitHub PRs and provides notifications when PRs change state.

## Proposed feature set

### MVP

- [X] Show state of all open PRs.
    - Show PR number + start of title.
    - States: draft, open (no review submitted), waiting for review, review requested from me, reviewed: changes requested, reviewed: approved, assigned to PR (?), merged.
    - Show if a PR has merge conflicts, or failing GitHub actions or merge is blocked for another reason.
    - *Seems like there are multiple types of states: merge status (conflicts, failing actions, other blockers (e.g., conversation must be resolved), ready to merge, merged), reviews (waiting, requested, reviewed: changes requested, reviewed: approved), other (assigned to PR, unassigned from PR).*
    - Review-state precedence for MVP triage: `changes requested` wins over everything, then any currently outstanding review requests, then prior approvals. If a PR was approved and later new reviewers are requested, the PR should display as waiting for review until those requests are satisfied.
- [X] Button that opens the url of the PR in web browser.
- Notification (including sound) when a tracked PR enters a status.

### V2

- User can select which repos are monitored for PRs.
- Ability to chose which state changes you get notified for.
    - UX: user selects which statuses they want to be notified for, then they are notfied when the PR enters that status.
    - Probs good for the user to be able to set if they want to be notified about: all PRs in repo, only PRs they’ve been assigned to, only relevant PRs (i.e.,
- Make it really easy for the user to provide the correct GitHub finegrain access token.
    - UX: during set up, user selects the settings that they want and then we work out which token they need and ask them for it.
    - If the user changes any settings which conflict with their finegrain token, then
    - UX: user can set when their token is due to expire and we remind them to renew it.
- Notification if you’re tagged in a PR main comment.
- Post a review reminder as a comment on the PR which tags the reviewers + leaves a user defined message.
- Notification if you’re tagged in a PR review comment.
- Notifications for GitHub issues.
    - Tagged, assigned, action on assigned PR.
- Merge mergeable PRs.
- Unsubscribe from notifications from a specific PR.
- Subscribe to notifications for a specific PR.
- Adjust PR prioritises.
- Set working hours.
- Catch up – tell the user what’s happened since they’ve been away.
- Button to open the worktree folder for that PR.
- Escalate a PR – escalate a PR so others see it as a priority. Perhaps this can be done by adding an "@user ESCALATE" comment to the PR and then checking for those.
- Ability to request a review from someone.
