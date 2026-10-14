#!/bin/zsh
# Builds a Release PaceBar.app into ./build, signed with the hardened runtime.
#   ./build.sh                 ad hoc signature (personal use)
#   SIGN_ID="Apple Development: …" ./build.sh   sign with a development identity
#   UNIVERSAL=1 ./build.sh     build for both Apple silicon and Intel
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="build/PaceBar.app"
ENTITLEMENTS="Resources/PaceBar.entitlements"

ARCH_FLAGS=()
[[ -n "${UNIVERSAL:-}" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCH_FLAGS[@]}" --product PaceBar
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PaceBar" "$APP/Contents/MacOS/PaceBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Records the source commit for the About tab, marked "-dirty" if there were uncommitted changes.
if COMMIT="$(git rev-parse --short HEAD 2>/dev/null)"; then
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && COMMIT="$COMMIT-dirty"
    /usr/libexec/PlistBuddy -c "Add :PaceBarCommit string $COMMIT" "$APP/Contents/Info.plist"
fi

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf "${ICONSET:h}"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Notarization needs a secure timestamp; an ad hoc signature can't have one.
TIMESTAMP="--timestamp"
[[ -z "${SIGN_ID:-}" || "$SIGN_ID" == "-" ]] && TIMESTAMP="--timestamp=none"

codesign --force --sign "${SIGN_ID:--}" --options runtime "$TIMESTAMP" \
    --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo
echo "Built $APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null \
    | grep -o 'com\.apple\.security\.[A-Za-z0-9.-]*' | sed 's/^/  entitlement: /'
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|CodeDirectory|Authority=Developer ID Application|Timestamp)' | sed 's/^/  /'
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/PaceBar")"
