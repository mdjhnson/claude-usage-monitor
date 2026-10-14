#!/bin/zsh
# Builds PaceBar, quits the running copy, installs it to /Applications and relaunches it.
#   ./deploy.sh                skip the relaunch with NO_LAUNCH=1
# Build options such as TEAM_ID and SIGN_ID pass through to build.sh.
set -euo pipefail
cd "${0:A:h}"

SRC="build/PaceBar.app"
DEST="/Applications/PaceBar.app"

# macOS caches each app's widget list and only re-reads it when the build number changes, so
# every local install gets its own: Info.plist's number plus a timestamp, e.g. 1.2610141705.
BASE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
export BUILD_NUMBER="${BUILD_NUMBER:-$BASE_BUILD.$(date +%y%m%d%H%M)}"

# Build first, so a failed build leaves the installed copy running.
./build.sh

if pgrep -xq PaceBar; then
    echo "Quitting PaceBar…"
    pkill -x PaceBar
    for _ in {1..50}; do
        pgrep -xq PaceBar || break
        sleep 0.1
    done
    if pgrep -xq PaceBar; then
        echo "PaceBar didn't quit in 5 seconds; forcing it."
        pkill -9 -x PaceBar
    fi
fi

rm -rf "$DEST"
ditto "$SRC" "$DEST"
codesign --verify --strict "$DEST"
echo "Installed $DEST"

# macOS keeps a running widget extension alive across an app update, so widgets would keep
# drawing with the old code. Quitting it makes WidgetKit start the new one.
pkill -x PaceBarWidget 2>/dev/null && echo "Restarted the widget extension" || true

if [[ -z "${NO_LAUNCH:-}" ]]; then
    open "$DEST"
    echo "Launched PaceBar"
fi
