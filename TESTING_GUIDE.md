# Development Setup

## Prerequisites

- **macOS 14.0+**
- **Xcode 26.4** (includes `swift format`)
- **[mise](https://mise.jdx.dev/)** for tool and task management
- A **GitHub account** with at least one open pull request you're involved in

## First-Time Setup

```bash
mise install
mise run sync
mise run hooks:install
```

`mise install` provisions the repo-managed tools defined in [`mise.toml`](mise.toml):

| Tool | Purpose |
| --- | --- |
| `swiftlint` | Swift policy enforcement |
| `xcodegen` | Regenerate `GitHubCommandCenter.xcodeproj` from `project.yml` |
| `hk` | Git hook manager |
| `pkl` | Configuration runtime required by `hk` |

`swift format` ships with Xcode, so there is no separate formatter install.

## Mise Tasks

Run any task with `mise run <task>`:

| Task | Description |
| --- | --- |
| `sync` | Install tools and regenerate the Xcode project |
| `open` | Open the generated Xcode project |
| `build` | Build the app with `xcodebuild` |
| `build-release` | Build the release app bundle into `build/DerivedData` |
| `test` | Run the Swift test suite with `xcodebuild` |
| `check-style` | Run `swift format` linting and `swiftlint` in read-only mode |
| `fix-style` | Apply `swift format` and `swiftlint` fixes |
| `check` | Run the full verification workflow |
| `fix` | Regenerate the project and apply style fixes |
| `hooks:install` | Install git hooks through `hk` |

## Swift Formatting and Linting

The repo uses a two-tool setup:

### 1. `swift format`

`swift format` handles formatting such as indentation, wrapping, spacing, and import ordering. Configuration lives in [`.swift-format`](.swift-format).

Key settings:

- Line length: `120`
- Indentation: `4` spaces
- Maximum blank lines: `1`
- Trailing commas: required in multiline collections
- File-scoped declarations: `private`
- Break before each argument when wrapping

Manual commands:

```bash
# Check only
swift format lint --strict --recursive GitHubCommandCenter GitHubCommandCenterTests

# Fix in place
swift format --in-place --recursive GitHubCommandCenter GitHubCommandCenterTests
```

### 2. `SwiftLint`

`SwiftLint` enforces policy rules such as size limits, force unwrap usage, and naming. Configuration lives in [`.swiftlint.yml`](.swiftlint.yml).

Formatting-overlap rules are disabled so `swift format` remains the single source of truth for code layout.

Notable thresholds:

| Rule | Warning | Error |
| --- | --- | --- |
| `line_length` | 120 | 200 |
| `file_length` | 700 | 1000 |
| `function_body_length` | 110 | 140 |
| `type_body_length` | 600 | 700 |
| `cyclomatic_complexity` | 20 | 30 |
| `identifier_name` minimum | 2 chars | 1 char |

Opt-in policy rules include `force_unwrapping`, `implicitly_unwrapped_optional`, `empty_count`, `first_where`, `toggle_bool`, and `modifier_order`.

Allowed short identifiers: `id`, `x`, `y`, `i`, `j`, `k`.

Manual commands:

```bash
# Check
swiftlint lint --strict

# Fix
swiftlint lint --fix
```

### Combined style tasks

```bash
mise run check-style
mise run fix-style
```

## Git Hooks

Git hooks are managed by [`hk`](https://github.com/jdx/hk) using [`hk.pkl`](hk.pkl).

Install hooks with:

```bash
mise run hooks:install
```

The `pre-commit` hook:

1. Stashes unstaged changes with `stash = "git"`
2. Runs `mise run fix-style` when staged Swift files are present
3. Re-runs `mise run check-style` to make sure the fixes are clean
4. Runs trailing-whitespace and merge-conflict checks
5. Re-stages files updated by the fix step

## Build, Run, and Test

### Command line

```bash
mise run build
mise run test
```

To open the project in Xcode:

```bash
mise run open
```

### Xcode

1. Run `mise run sync` if `project.yml` changed
2. Open `GitHubCommandCenter.xcodeproj`
3. Select the **GitHubCommandCenter** scheme
4. Set the destination to **My Mac**
5. Press **Cmd+B** to build or **Cmd+U** to run tests

## Manual App Testing

### 1. Create a GitHub personal access token

1. Go to <https://github.com/settings/tokens> or <https://github.com/settings/tokens?type=beta>
2. Generate either:
   - A classic token with the `repo` scope, or
   - A fine-grained token with **Pull requests: Read**, **Commit statuses: Read**, and **Checks: Read**
3. Copy the token

### 2. Launch the app

1. Build with `mise run build` or run the app from Xcode with **Cmd+R**
2. Look for the menu bar icon at the top of the screen

### 3. Configure the token

1. Open the menu bar app
2. Open **Settings**
3. Paste the token into **Paste your GitHub token here**
4. Click **Save Token**
5. Confirm you see **Connected as @yourusername**

### 4. Verify behavior

1. Open the menu bar panel
2. Confirm PR titles, repo names, review state, draft state, and CI indicators match GitHub
3. Confirm the icon color matches repo health
4. Click a PR row and verify it opens in the browser

## Troubleshooting

| Problem | Solution |
| --- | --- |
| `mise run sync` fails because tools are missing | Run `mise install` first |
| `swiftlint` is not found | Run `mise install` so the repo-managed version is installed |
| Build fails with signing errors | Use the `mise run build` task, which disables code signing for local builds |
| `GitHubCommandCenter.xcodeproj` is stale | Run `mise run sync` after changing `project.yml` |
| Hooks do not run | Reinstall them with `mise run hooks:install` |
| Token validation fails | Ensure the token has the required `repo` scope or the fine-grained read permissions listed above |
| PRs load but CI detail looks incomplete | Add **Checks: Read** to the fine-grained token; without it the app falls back to commit statuses only |
