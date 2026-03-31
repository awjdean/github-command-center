## Project

Swift/SwiftUI macOS 14+ menu bar app monitoring GitHub PR status. No external Swift dependencies.

## Build & Test (CLI)

- First-time setup: `mise install`
- Sync tools and regenerate the Xcode project: `mise run sync`
- Build: `mise run build`
- Test: `mise run test`
- Style checks: `mise run check`
- Fix, then re-run style checks and tests: `mise run verify`
- After editing `project.yml`: run `mise run sync`

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review
