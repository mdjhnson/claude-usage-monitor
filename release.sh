#!/bin/zsh
# Builds a universal PaceBar.app, has Xcode sign it with the team's cloud-managed Developer ID
# certificate and notarize it, then packages the stapled app as dist/PaceBar-<version>.dmg.
#   TEAM_ID=ABCDE12345 ./release.sh
#   PUBLISH=1 TEAM_ID=… ./release.sh   also publish it: the DMG goes to PaceBar's page on the staff
#                                      site (scripts/publish-staff-site.sh), then GitHub Release
#                                      v<version> is created with notes and no DMG attached. Check
#                                      for Updates reads the version from GitHub; the download stays
#                                      behind the staff site's Campus Outreach sign-in.
# Needs Xcode signed in (Settings › Accounts) to an account on that team with
# "Access to Cloud Managed Developer ID Certificate". No local certificate or notary password.
# One-time setup is in README.md under "Distributing to others".
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="build/PaceBar.app"
PLIST="Resources/Info.plist"
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
BUNDLE_ID="$(plist_value CFBundleIdentifier)"
VERSION="$(plist_value CFBundleShortVersionString)"
BUILD="$(plist_value CFBundleVersion)"
DMG="dist/PaceBar-$VERSION.dmg"
# How long to wait for Apple's notary service before giving up.
NOTARY_TIMEOUT_SECONDS=1800

TAG="v$VERSION"

if [[ -z "${TEAM_ID:-}" ]]; then
    echo "Set TEAM_ID to your Apple Developer team ID, e.g. TEAM_ID=ABCDE12345 ./release.sh" >&2
    exit 1
fi

# Checked before the build, so a publish that can't succeed fails in seconds, not after notarizing.
if [[ -n "${PUBLISH:-}" ]]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "PUBLISH=1 needs the GitHub CLI signed in: run gh auth login." >&2
        exit 1
    fi
    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "GitHub Release $TAG already exists. Bump CFBundleShortVersionString in $PLIST first." >&2
        exit 1
    fi
    # The release must be tagged at exactly the commit being built, so the tag, its notes and
    # the source archive match the DMG. A leftover tag would point somewhere else.
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        echo "Tag $TAG already exists. Delete it or bump CFBundleShortVersionString in $PLIST first." >&2
        exit 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "PUBLISH=1 needs a clean tree, so the release matches a commit. Commit or stash first." >&2
        exit 1
    fi
    git fetch -q origin
    if [[ -z "$(git branch -r --contains HEAD)" ]]; then
        echo "Push $(git rev-parse --short HEAD) to GitHub first; the tag is created on that commit." >&2
        exit 1
    fi
    # The staff-site token is in the keychain and the tool page exists. Changes nothing.
    scripts/publish-staff-site.sh --check
fi
COMMIT="$(git rev-parse HEAD)"

# Ad hoc here; exporting re-signs the app and its widget with the Developer ID certificate.
# TEAM_ID still names the App Group, so it matches the team that signs the export.
SIGN_ID=- ./build.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ARCHIVE="$WORK/PaceBar.xcarchive"

# Wrap the ad hoc signed build in the archive layout xcodebuild expects. Exporting it re-signs
# the app and the embedded widget with the Developer ID certificate.
mkdir -p "$ARCHIVE/Products/Applications"
ditto "$APP" "$ARCHIVE/Products/Applications/PaceBar.app"
cat >"$ARCHIVE/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ApplicationProperties</key>
	<dict>
		<key>ApplicationPath</key>
		<string>Applications/PaceBar.app</string>
		<key>Architectures</key>
		<array><string>arm64</string><string>x86_64</string></array>
		<key>CFBundleIdentifier</key>
		<string>$BUNDLE_ID</string>
		<key>CFBundleShortVersionString</key>
		<string>$VERSION</string>
		<key>CFBundleVersion</key>
		<string>$BUILD</string>
		<key>Team</key>
		<string>$TEAM_ID</string>
	</dict>
	<key>ArchiveVersion</key>
	<integer>2</integer>
	<key>CreationDate</key>
	<date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
	<key>Name</key>
	<string>PaceBar</string>
	<key>SchemeName</key>
	<string>PaceBar</string>
</dict>
</plist>
EOF
# destination "upload" signs the app and submits it to Apple's notary service.
cat >"$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>destination</key>
	<string>upload</string>
</dict>
</plist>
EOF
plutil -lint "$ARCHIVE/Info.plist" "$WORK/ExportOptions.plist" >/dev/null

echo "Signing with the cloud-managed Developer ID and submitting for notarization…"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/upload" \
        -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates >"$WORK/upload.log" 2>&1; then
    cat "$WORK/upload.log" >&2
    echo "Export failed. Is Xcode signed in to team $TEAM_ID with cloud-managed Developer ID access?" >&2
    exit 1
fi

# exportNotarizedApp fails with "is processing" until Apple finishes, then exports the stapled app.
echo "Waiting for Apple to notarize (usually a minute or two)…"
NOTARIZED="$WORK/notarized/PaceBar.app"
deadline=$(( SECONDS + NOTARY_TIMEOUT_SECONDS ))
until [[ -d "$NOTARIZED" ]]; do
    if out="$(xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$WORK/notarized" \
            -allowProvisioningUpdates 2>&1)"; then
        continue
    fi
    if [[ "$out" != *"is processing"* ]]; then
        echo "$out" >&2
        echo "Notarization failed." >&2
        exit 1
    fi
    if (( SECONDS > deadline )); then
        echo "Gave up after $NOTARY_TIMEOUT_SECONDS seconds; Apple is still processing." >&2
        exit 1
    fi
    sleep 15
done

xcrun stapler validate "$NOTARIZED" >/dev/null
spctl --assess --type execute "$NOTARIZED"
codesign --verify --strict --deep "$NOTARIZED"

# The DMG itself stays unsigned: the cloud certificate only signs through Xcode. Gatekeeper
# checks the stapled app inside when it's opened, so this doesn't cause a warning.
mkdir -p "$WORK/dmg" dist
ditto "$NOTARIZED" "$WORK/dmg/PaceBar.app"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "$DMG"
if ! hdiutil create -volname "PaceBar" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG" \
        >"$WORK/hdiutil.log" 2>&1; then
    cat "$WORK/hdiutil.log" >&2
    exit 1
fi

echo
codesign -dvv "$NOTARIZED" 2>&1 | grep -E '^Authority=Developer ID Application' | sed 's/^/  /'
codesign -dvv "$NOTARIZED/Contents/PlugIns/PaceBarWidget.appex" 2>&1 \
    | grep -E '^Authority=Developer ID Application' | sed 's/^/  widget: /'
spctl --assess --type execute --verbose=2 "$NOTARIZED" 2>&1 | grep '^source=' | sed 's/^/  /'
echo "  architectures: $(lipo -archs "$NOTARIZED/Contents/MacOS/PaceBar")"
echo "Built $DMG"

# No DMG on GitHub: the repository is public and the installer is for staff. The notes say where
# it is. --notes goes above the generated list of changes.
NOTES="**Staff:** download PaceBar $VERSION from https://staff-services.serve.campusoutreach.org/tools/pacebar (Campus Outreach sign-in). This release has no download attached."
STAFF_CMD=(scripts/publish-staff-site.sh "$DMG")
PUBLISH_CMD=(gh release create "$TAG" --target "$COMMIT" --title "PaceBar $VERSION" --notes "$NOTES" --generate-notes)
echo
if [[ -n "${PUBLISH:-}" ]]; then
    # Staff site first, so the download is there by the time Check for Updates sees the version.
    "${STAFF_CMD[@]}"
    echo "Publishing GitHub Release $TAG…"
    if ! "${PUBLISH_CMD[@]}"; then
        echo "The staff site has $VERSION, but the GitHub Release failed. Retry it with:" >&2
        echo "  ${(q)PUBLISH_CMD[@]}" >&2
        exit 1
    fi
else
    echo "To publish it, upload to the staff site, then create the GitHub Release Check for Updates reads:"
    echo "  ${(q)STAFF_CMD[@]}"
    echo "  ${(q)PUBLISH_CMD[@]}"
fi
