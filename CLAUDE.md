# CLAUDE.md

PaceBar is a macOS menu bar app, with desktop and Notification Center widgets, that shows Claude usage limits and pacing. `PaceBar.xcodeproj` (generated from `project.yml` by XcodeGen; edit the YAML, run `xcodegen`, commit both) builds the app, the widget extension and PaceBarCore. `Package.swift` builds PaceBarCore for `swift test` only. README.md is the source of truth for behavior, settings and the security design. BRIEF.md is the original spec, kept as history. DESIGN_NOTES.md is the visual spec.

## Commands

```sh
./test.sh                   # unit tests (PaceBarCore)
./scripts/audit.sh          # security rules; must pass before every commit
./build.sh                  # build/PaceBar.app + widget, signed with the Apple Development cert's team (TEAM_ID=… to pick)
./deploy.sh                 # build, install to /Applications, relaunch
TEAM_ID=… ./release.sh  # notarized universal DMG in dist/
```

Scripts use Xcode via `DEVELOPER_DIR`; `xcode-select` points at the Command Line Tools, so don't call bare `xcodebuild` without it.

## Rules

- The app holds a full-scope Claude Code OAuth token. `scripts/audit.sh` enforces the security design: two network hosts (`api.anthropic.com` for usage, with the token; `api.github.com` for the opt-in update check, one fixed URL in `UpdateClient.swift`, never with the token), one subprocess, one app launch (Terminal.app), exactly three opened URLs (the About tab's repo link and staff-site download link, and the Notifications tab's System Settings link), one written file (the widget snapshot, from `WidgetSnapshot.swift`), one Darwin notification (the widgets' data-free refresh request), and a sandboxed widget with no network, Keychain or subprocess code. Adding a URL, link, subprocess, app launch, file write or entitlement means changing the audit rule narrowly and updating README's "Threat model and security design" and "Auditing" sections in the same change.
- Never log, persist or copy the token, and never put it (or anything from the Keychain) in `WidgetSnapshot`. Keep pure logic in `Sources/PaceBarCore` with tests.
- When a setting or tab changes, update the README Settings table.

## Workflow

- Run `git pull` on `main` before starting; local `main` has fallen behind GitHub before.
- Work on a feature branch and open a PR; `main` changes land through merged PRs.
- Version bumps in `Resources/Info.plist` are the maintainer's; don't commit them unless asked.

## Releases

`PUBLISH=1 ./release.sh` puts the DMG on the staff site (`scripts/publish-staff-site.sh`, token in the keychain as `pacebar-staff-site`) and creates a GitHub Release with no DMG attached; the `release` skill walks through it. `release.sh` signs with the team's **cloud-managed** Developer ID certificate through `xcodebuild -exportArchive` (method `developer-id`, destination `upload`), which also notarizes using the Xcode-signed-in account. There is no local Developer ID certificate or notarytool profile, and none is needed. The DMG itself is unsigned by design; the app inside is stapled. The team ID lives in the gitignored `DEPLOYMENT_COMMANDS.md`, not in tracked files. Settings › About shows the build's commit, from `PaceBarCommit` that `build.sh` writes, with `-dirty` for uncommitted changes, so release from a clean tree.
