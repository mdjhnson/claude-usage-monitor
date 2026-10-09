#!/bin/zsh
# Builds PaceBar, quits the running copy, installs it to /Applications and relaunches it.
#   ./deploy.sh                skip the relaunch with NO_LAUNCH=1
# Build options such as SIGN_ID pass through to build.sh.
set -euo pipefail
cd "${0:A:h}"

SRC="build/PaceBar.app"
DEST="/Applications/PaceBar.app"

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

if [[ -z "${NO_LAUNCH:-}" ]]; then
    open "$DEST"
    echo "Launched PaceBar"
fi
