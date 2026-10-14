#!/bin/zsh
# Builds a Release PaceBar.app, with its widget extension, into ./build.
#   ./build.sh                      signed with your Apple Development certificate, for its team
#   TEAM_ID=… ./build.sh            the same, for a team you pick
#   TEAM_ID=… SIGN_ID=- ./build.sh  ad hoc signature (release.sh uses this; exporting re-signs it)
#   BUILD_NUMBER=… ./build.sh       override CFBundleVersion for the app and widget (deploy.sh does)
# The app and the widget share an App Group named after the team, and macOS only lets them use
# it when they're signed by that team, so every build needs one. Builds are universal.
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Team IDs (the certificate's OU) of the Apple Development identities in the keychain.
development_teams() {
    security find-certificate -a -c "Apple Development" -p 2>/dev/null \
        | awk '/BEGIN CERT/ { cert = "" } { cert = cert $0 "\n" } /END CERT/ { printf "%s", cert | "openssl x509 -noout -subject"; close("openssl x509 -noout -subject") }' \
        | sed -nE 's/.*OU *= *([A-Z0-9]{10}).*/\1/p' | sort -u
}

if [[ "${SIGN_ID:-}" != "-" ]]; then
    teams=(${(f)"$(development_teams)"})
    if [[ -z "${TEAM_ID:-}" ]]; then
        if (( ${#teams} == 1 )); then
            TEAM_ID="${teams[1]}"
            echo "Using team $TEAM_ID from your Apple Development certificate."
        else
            echo "Set TEAM_ID to the team to sign with, for example TEAM_ID=ABCDE12345 ./build.sh." >&2
            (( ${#teams} )) && echo "Teams with an Apple Development certificate here: ${teams[*]}" >&2
            echo "Without one, sign in to Xcode › Settings › Accounts (a free Personal Team works) and" >&2
            echo "choose Manage Certificates › + › Apple Development." >&2
            exit 1
        fi
    elif (( ! ${teams[(Ie)$TEAM_ID]} )); then
        echo "There's no Apple Development certificate for team $TEAM_ID in your keychain." >&2
        (( ${#teams} )) && echo "Teams that have one: ${teams[*]}. Local builds can use any of them." >&2
        echo "Releases don't need one: release.sh signs with the team's cloud-managed Developer ID." >&2
        exit 1
    fi
elif [[ -z "${TEAM_ID:-}" ]]; then
    echo "An ad hoc build still needs TEAM_ID, to name the App Group the release will be signed for." >&2
    exit 1
fi

APP="build/PaceBar.app"
WIDGET="$APP/Contents/PlugIns/PaceBarWidget.appex"
DERIVED="build/DerivedData"

EXTRA_SETTINGS=()
[[ -n "${BUILD_NUMBER:-}" ]] && EXTRA_SETTINGS=("PACEBAR_BUILD_NUMBER=$BUILD_NUMBER")

# Scripts in the project stamp the commit, draw the icon and match the widget's version.
xcodebuild -project PaceBar.xcodeproj -scheme PaceBar -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" -quiet \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="${SIGN_ID:-Apple Development}" \
    "${EXTRA_SETTINGS[@]}" build

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/PaceBar.app" "$APP"
codesign --verify --strict --deep --verbose=1 "$APP"

echo
echo "Built $APP"
for bundle in "$APP" "$WIDGET"; do
    echo "${bundle:t}:"
    codesign -d --entitlements - --xml "$bundle" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null \
        | grep -o 'com\.apple\.security\.[A-Za-z0-9.-]*' | sed 's/^/  entitlement: /'
    codesign -dv "$bundle" 2>&1 | grep -E '^(Identifier|TeamIdentifier|Authority=Developer ID Application|Timestamp)' | sed 's/^/  /'
done
echo "  app group: $(/usr/libexec/PlistBuddy -c 'Print :PaceBarAppGroup' "$APP/Contents/Info.plist")"
echo "  version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"))"
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/PaceBar")"
