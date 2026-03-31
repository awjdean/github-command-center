# UX Improvements

- [X] Move the "Quit" and the "Launch at login" options into Settings.
- [X] User can't edit GitHub token after it has been entered + verified. then must remove it.
- [X] Show the user which repos are being tracked.
- [X] Make the "Accessible repos" section in Settings be collapsible. It's default state should be collapsed.
- [X] Displayed number in the menu bar should be the number of PRs that need your attention, not the number of PRs being tracked.
- [X] Only send the user to the GitHub link for the PR when the PR number is clicked.
- [ ] Ability to reorder PRs.
- [X] It doesn't really make sense to have your draft PRs in the "Waiting on others" section when they're not waiting on others. Let's add a 3rd section: "Your draft PRs" containing any PRs that are drafts and that you either created or are assigned to.
- [X] We want it so that if we click on the indicators, the tool tips appear straight away.
- [ ] Make the dropdown bigger.
- [X] On the Settings view, remove the text immediately under Settings that says "Authentication and app settings".
- [ ] Provide all info for failing CI in the info popup.
- [ ] Add a loading state for the menu bar icon when the app is first loading up.


- [ ] Better UX once a token has been added.

Bug
- [ ] When a PR is in draft the CI indicator always shows "Checking mergeability" whatever is actually happening to the CI. Can we please make it so that the CI indicator
- [ ] PRs that are in draft, that you didn't create and are not assigned to should not appear in the app.

# Features


# Efficency
- [ ] Don't poll draft PRs.
