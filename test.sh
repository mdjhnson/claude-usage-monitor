#!/bin/zsh
# Runs every unit test. Uses Xcode's toolchain without changing xcode-select.
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec swift test "$@"
