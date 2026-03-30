# Testing Guide: GitHub Command Center

Step-by-step instructions for building, running, and manually testing the app.

---

## Prerequisites

- **macOS 13.0+** (Ventura or later)
- **Xcode 16+** (verify: `xcode-select -p` should print a path)
- **XcodeGen** (verify: `which xcodegen` — install with `brew install xcodegen` if missing)
- A **GitHub account** with at least one open pull request you're involved in

---

## Step 1: Create a GitHub Personal Access Token

1. Go to <https://github.com/settings/tokens> (classic tokens) or <https://github.com/settings/tokens?type=beta> (fine-grained)
2. Click **"Generate new token"**
3. For a **classic token**:
   - Give it a descriptive name (e.g. "Command Center")
   - Select the **`repo`** scope (this grants read access to your PRs, reviews, and CI status)
   - Click **Generate token**
4. For a **fine-grained token**:
   - Set repository access to **"All repositories"** (or select specific repos)
   - Under **Repository permissions**, grant **Pull requests: Read** and **Commit statuses: Read**
   - Click **Generate token**
5. **Copy the token** — you won't be able to see it again

---

## Step 2: Generate the Xcode Project

From the repo root:

```bash
cd /Users/awjdean/coding/github-command-center
xcodegen generate
```

This reads `project.yml` and produces `GitHubCommandCenter.xcodeproj`.

---

## Step 3: Build the App

### Option A: Xcode GUI

1. Open `GitHubCommandCenter.xcodeproj` in Xcode
2. Select the **GitHubCommandCenter** scheme (top-left dropdown)
3. Set the destination to **My Mac**
4. Press **Cmd+B** to build

### Option B: Command line

```bash
xcodebuild \
  -project GitHubCommandCenter.xcodeproj \
  -scheme GitHubCommandCenter \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

---

## Step 4: Run the App

### Option A: Xcode GUI

Press **Cmd+R** in Xcode. The app has no Dock icon (it's a menu bar-only app via `LSUIElement`), so look for a new icon in your **menu bar** at the top of the screen.

### Option B: Run the built binary directly

After a successful build, find and launch the binary:

```bash
# Find the built app
find ~/Library/Developer/Xcode/DerivedData -name "GitHubCommandCenter.app" -type d 2>/dev/null | head -1

# Launch it (substitute the actual path from above)
open "<path>/GitHubCommandCenter.app"
```

---

## Step 5: Configure Your Token

1. The menu bar icon should appear (a small icon in the top bar)
2. **Click the menu bar icon** — a dropdown panel will open
3. Since no token is configured yet, you'll see a setup prompt
4. Open **Settings**:
   - Right-click the menu bar icon, or
   - From the panel, look for a settings/gear option, or
   - Use **Cmd+,** while the app is focused
5. In the Settings window:
   - Paste your GitHub token into the **"Paste your GitHub token here"** field
   - Click **"Save Token"**
   - Wait for validation — you should see a green checkmark and **"Connected as @yourusername"**
   - If you see a red X with "Invalid token", double-check the token and its scopes

---

## Step 6: Verify It Works

Once the token is saved and validated:

1. **Click the menu bar icon** — the panel should now show your open PRs
2. Verify the following for each PR:
   - PR title and repo name are correct
   - CI status indicators (passing/failing/pending) match what you see on GitHub
   - Review status (approved, changes requested, pending review) is accurate
   - Draft status is shown correctly
3. The menu bar icon color should reflect your PR health:
   - **Green** — no PRs need your action
   - **Yellow** — some PRs need attention
   - **Red** — urgent PRs need your action
4. **Click a PR row** — it should open the PR in your browser

---

## Step 7: Run the Unit Tests

### Option A: Xcode GUI

Press **Cmd+U** in Xcode.

### Option B: Command line

```bash
xcodebuild \
  -project GitHubCommandCenter.xcodeproj \
  -scheme GitHubCommandCenter \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  test
```

This runs the test suite in `GitHubCommandCenterTests/`, which includes:
- `PRStateTests` — PR model logic and triage sorting
- `GitHubRESTClientTests` — API response parsing with mock networking
- `PollingEngineTests` — polling lifecycle and state updates
- `NotificationServiceTests` — notification triggering logic
- `KeychainServiceTests` — token storage and retrieval

---

## Troubleshooting

| Problem | Solution |
|---|---|
| **"Invalid token"** after saving | Ensure the token has the `repo` scope. Fine-grained tokens need Pull requests + Commit statuses read access. |
| **No menu bar icon appears** | The app is `LSUIElement` (no Dock icon). Look carefully in the menu bar. If running via Xcode, check the console for crash logs. |
| **Build fails with signing errors** | Use the CLI build command above which disables code signing, or in Xcode set Signing to "Sign to Run Locally". |
| **"Rate limit exceeded"** | The GitHub API allows 5,000 requests/hour for authenticated users. If you have many PRs, wait for the reset time shown in the app. |
| **PRs not showing up** | The app searches for PRs where you are involved (author, reviewer, assignee, mentioned). Check that your token username matches. |
| **Stale data indicator** | If data is >5 minutes old, the app marks it as stale. Click refresh or wait for the next automatic poll. |
| **XcodeGen not found** | Install with `brew install xcodegen` |
| **Xcode project out of date** | Run `xcodegen generate` after any changes to `project.yml` |
