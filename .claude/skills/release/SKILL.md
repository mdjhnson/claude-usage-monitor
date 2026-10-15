---
name: release
description: Release a new PaceBar version to staff - bump the version, build and notarize the DMG, put it on the staff site's PaceBar page, and create the GitHub Release that Check for Updates reads. Use when asked to release, ship, publish or cut a new PaceBar version.
---

# Releasing PaceBar

A release has two halves that must agree:

- **The DMG goes to the staff site**, at `https://staff-services.serve.campusoutreach.org/tools/pacebar`, behind its Campus Outreach sign-in. `/tools/pacebar/download` always serves the current file, and Settings › About's Download link points at the page. The DMG is never attached to GitHub, because the repository is public.
- **The GitHub Release `v<version>`** carries notes but no DMG. Check for Updates reads its tag, so it must not appear before the staff site has the file.

`PUBLISH=1 ./release.sh` does both in that order. This skill is the routine around it. Stop and ask at any step that fails; don't work around a failed check.

## 1. Preflight

Run these, and stop if any fails:

- `git checkout main && git pull --ff-only`. The release is built from `main`, never a feature branch.
- `git status --porcelain` is empty.
- `./test.sh` and `./scripts/audit.sh` pass.
- `gh auth status` is signed in.
- `scripts/publish-staff-site.sh --check` prints "token works". If it fails, the token is missing from the keychain or expired. The user (a staff-site admin) has to create a new one at `/_emdash/admin` with only `content:read`, `content:write` and `media:write`, then run `security add-generic-password -U -s pacebar-staff-site -a release -w`. Never ask them to paste the token into the chat, and never put it in a file, an argument or an environment variable.
- Read the team ID from the gitignored `DEPLOYMENT_COMMANDS.md`. Don't write it into tracked files.

## 2. Choose the version

Read `CFBundleShortVersionString` from `Resources/Info.plist`, and list the merged PRs since the last tag (`git log --oneline $(git describe --tags --abbrev=0 2>/dev/null)..HEAD`, or every commit if there is no tag). Propose a version: minor for features, patch for fixes only. Confirm it with the user; the version is theirs to choose (CLAUDE.md).

Then bump `CFBundleShortVersionString` and increment `CFBundleVersion` on a branch, open a PR, and wait for the user to merge it. `release.sh` refuses to tag a commit that isn't on GitHub. After the merge, `git checkout main && git pull --ff-only`.

## 3. Build, notarize, publish

```sh
PUBLISH=1 TEAM_ID=<from DEPLOYMENT_COMMANDS.md> ./release.sh
```

Run it in the background; notarization usually takes a few minutes. The script:

1. checks `gh`, the tag, a clean pushed tree, and the staff-site token before building
2. builds, signs with the cloud-managed Developer ID, notarizes and staples, and packages `dist/PaceBar-<version>.dmg`
3. uploads the DMG to the staff site and publishes the PaceBar entry
4. creates GitHub Release `v<version>` at exactly the built commit, with staff notes and generated notes

If step 4 fails after step 3, the staff site already has the new version. Re-run only the `gh release create` command the script prints. Don't re-run `release.sh`; it would refuse the existing tag or rebuild for nothing.

## 4. Verify

- `gh release view v<version>`: the notes point to the staff page, and there are **no assets**.
- `scripts/publish-staff-site.sh --check` still passes, and the script's own last line said "now offers PaceBar-<version>.dmg".
- Ask the user to open `https://staff-services.serve.campusoutreach.org/tools/pacebar` while signed in and confirm the page and the file name. Nothing else can check it: the download route needs a browser session, which the token doesn't provide.
- On a Mac running the previous version, Settings › About › Check for Updates should say "PaceBar <version> is available".

## 5. Tell staff

Draft a short announcement for the user to post. Leave it unsent; posting is theirs to do. It should cover:

- what's new, in plain words, from the merged PRs
- the link `https://staff-services.serve.campusoutreach.org/tools/pacebar`
- how to install: open the DMG, drag PaceBar to Applications, replace the old copy

## Don't

- Don't attach the DMG to the GitHub Release or upload it anywhere public.
- Don't release from a dirty tree or a feature branch. Settings › About shows the build's commit, marked `-dirty`.
- Don't print, log or copy the staff-site token. It can edit any page on the staff site.
- Don't change the staff-site entry's other fields from a script. Wording, logo and owner are edited in the admin.
