#!/bin/zsh
# Builds a Release PaceBar.app into ./build, signed with the hardened runtime.
#   ./build.sh                 ad hoc signature (personal use)
#   SIGN_ID="Apple Development: …" ./build.sh   sign with a development identity
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="build/PaceBar.app"
ENTITLEMENTS="Resources/PaceBar.entitlements"

swift build -c release --product PaceBar
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PaceBar" "$APP/Contents/MacOS/PaceBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --sign "${SIGN_ID:--}" --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo
echo "Built $APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null \
    | grep -o 'com\.apple\.security\.[A-Za-z0-9.-]*' | sed 's/^/  entitlement: /'
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|CodeDirectory)' | sed 's/^/  /'
