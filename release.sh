#!/bin/zsh
# Builds a universal PaceBar.app, has Xcode sign it with the team's cloud-managed Developer ID
# certificate and notarize it, then packages the stapled app as dist/PaceBar-<version>.dmg.
#   TEAM_ID=ABCDE12345 ./release.sh
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

if [[ -z "${TEAM_ID:-}" ]]; then
    echo "Set TEAM_ID to your Apple Developer team ID, e.g. TEAM_ID=ABCDE12345 ./release.sh" >&2
    exit 1
fi

# Ad hoc here; exporting re-signs the app and its widget with the Developer ID certificate.
# TEAM_ID still names the App Group, so it matches the team that signs the export.
SIGN_ID=- UNIVERSAL=1 ./build.sh

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
