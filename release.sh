#!/bin/zsh
# Builds a universal PaceBar.app signed with a Developer ID, notarizes and staples it,
# then wraps it in a signed, notarized and stapled DMG at dist/PaceBar-<version>.dmg.
#   ./release.sh                             uses the only Developer ID Application identity in your keychain
#   SIGN_ID="Developer ID Application: …" ./release.sh
#   NOTARY_PROFILE=name ./release.sh         notarytool keychain profile (default: pacebar)
# One-time setup is in README.md under "Distributing to others".
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="build/PaceBar.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-pacebar}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/PaceBar-$VERSION.dmg"

if [[ -z "${SIGN_ID:-}" ]]; then
    ids=("${(@f)$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)}")
    ids=(${ids:#})
    if (( ${#ids} == 0 )); then
        echo "No Developer ID Application certificate in your keychain. See README.md, \"Distributing to others\"." >&2
        exit 1
    elif (( ${#ids} > 1 )); then
        echo "Found ${#ids} Developer ID Application identities; set SIGN_ID to pick one:" >&2
        printf '  %s\n' "${ids[@]}" >&2
        exit 1
    fi
    SIGN_ID="${ids[1]}"
fi
if [[ "$SIGN_ID" != "Developer ID Application:"* ]]; then
    echo "SIGN_ID must be a Developer ID Application identity, not: $SIGN_ID" >&2
    exit 1
fi
echo "Signing as: $SIGN_ID"

# Fail before building if the notary credentials are missing.
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No working notarytool profile named \"$NOTARY_PROFILE\". See README.md, \"Distributing to others\"." >&2
    exit 1
fi

# Submits a file for notarization, waits, and prints Apple's log if it isn't accepted.
notarize() {
    echo "Notarizing ${1:t}…"
    local result id notary_status
    result="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
    id="$(plutil -extract id raw - <<<"$result")"
    notary_status="$(plutil -extract status raw - <<<"$result")"
    if [[ "$notary_status" != "Accepted" ]]; then
        echo "Notarization of ${1:t} finished with status: $notary_status" >&2
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
}

UNIVERSAL=1 SIGN_ID="$SIGN_ID" ./build.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Notarize and staple the app itself, so it opens offline after being copied out of the DMG.
ditto -c -k --keepParent "$APP" "$WORK/PaceBar.zip"
notarize "$WORK/PaceBar.zip"
xcrun stapler staple "$APP"

mkdir -p "$WORK/dmg" dist
ditto "$APP" "$WORK/dmg/PaceBar.app"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "$DMG"
hdiutil create -volname "PaceBar" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
codesign --sign "$SIGN_ID" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Built $DMG"
