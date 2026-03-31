# UX Improvements

- [X] Move the "Quit" and the "Launch at login" options into Settings.
- [X] User can't edit GitHub token after it has been entered + verified. then must remove it.
- [X] Show the user which repos are being tracked.
- [X] Make the "Accessible repos" section in Settings be collapsible. It's default state should be collapsed.
- [X] Displayed number in the menu bar should be the number of PRs that need your attention, not the number of PRs being tracked.
- [X] Only send the user to the GitHub link for the PR when the PR number is clicked.
- [X] It doesn't really make sense to have your draft PRs in the "Waiting on others" section when they're not waiting on others. Let's add a 3rd section: "Your draft PRs" containing any PRs that are drafts and that you either created or are assigned to.
- [X] We want it so that if we click on the indicators, the tool tips appear straight away.
- [X] Make the dropdown bigger.
- [X] On the Settings view, remove the text immediately under Settings that says "Authentication and app settings".
- [X] Provide all info for failing CI in the info popup.
- [X] Add a loading state for the menu bar icon when the app is first loading up.


- [ ] Ability to reorder PRs.


# Bugs
- [ ] When a PR is in draft the CI indicator always shows "Checking mergeability" whatever is actually happening to the CI. Can we please make it so that the CI indicator info popup says the actual merability status.
- [ ] The plan(docking) PR (in draft) shows "Checks pending" when all the checks have passed.
- [ ] PRs that are in draft, that you didn't create and are not assigned to should not appear in the app.
- [ ] Failing CI checks show repeated info in the info pop up (e.g., meeko PR).


# Features
- [ ] in the CI checks info popup can we show for each action if it has failed (red x), is running (amber circle), or has passed (green tick).

# Efficency
- [ ] Don't poll draft PRs.


# Manual checks
- [ ] Test UX for adding a token.
- [ ] Efficiency check
- [ ] How are the "Your PR", "Assigned" labels decided.
- [ ] Notifications.
