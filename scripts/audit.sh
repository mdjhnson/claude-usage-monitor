#!/bin/bash
# Lists every security-relevant line in the app source so it can be reviewed in one sitting.
# Exits non-zero if more than one network host, more than one subprocess call site, or any
# forbidden construct is found.
set -u
cd "$(dirname "$0")/.." || exit 2

SRC="Sources"
TESTS="Tests"
RESOURCES="Resources"
status=0

section() { printf '\n== %s ==\n' "$1"; }
hits() { grep -rnF --include='*.swift' -- "$1" "$2" 2>/dev/null; }

echo "PaceBar source audit ($(date '+%Y-%m-%d %H:%M'))"

for pattern in 'http://' 'https://' 'Process(' 'URLSession' 'UserDefaults' 'print(' 'NSLog('; do
    section "$pattern  [Sources]"
    hits "$pattern" "$SRC" || echo "(none)"
done

section "Forbidden constructs  [Sources]"
forbidden=$(grep -rnE --include='*.swift' \
    -e 'kSecReturnData' -e 'SecItemAdd|SecItemUpdate|SecItemDelete' \
    -e 'osascript|NSAppleScript|OSAScript' -e '/bin/(ba|z)?sh' -e 'launchPath' \
    -e 'NWListener|bind\(|listen\(' -e 'NSAppleEventManager|handleGetURLEvent' \
    -e 'FileManager.*\.claude' -e 'NSPasteboard.*[Tt]oken' \
    "$SRC" 2>/dev/null)
if [ -n "$forbidden" ]; then echo "$forbidden"; status=1; else echo "(none)"; fi

if [ -d "$RESOURCES" ]; then
    section "Bundle configuration  [Resources]"
    if grep -q 'CFBundleURLTypes' "$RESOURCES"/*.plist 2>/dev/null; then
        echo "URL scheme handler declared (forbidden)"; status=1
    else
        echo "no URL scheme handlers"
    fi
    echo "entitlements:"
    grep -o 'com\.apple\.security\.[A-Za-z0-9.-]*' "$RESOURCES"/*.entitlements 2>/dev/null | sed 's/^/  /'
    extra=$(grep -o 'com\.apple\.security\.[A-Za-z0-9.-]*' "$RESOURCES"/*.entitlements 2>/dev/null \
        | grep -vx 'com.apple.security.network.client')
    if [ -n "$extra" ]; then echo "unexpected entitlement(s) present"; status=1; fi
fi

section "Tests (informational: stubbed sessions and fixtures live here)"
for pattern in 'https://' 'URLSession' 'Process(' 'UserDefaults'; do
    count=$(hits "$pattern" "$TESTS" | wc -l | tr -d ' ')
    printf '%-14s %s hit(s)\n' "$pattern" "$count"
done

section "Summary"
hosts=$(grep -rhoE --include='*.swift' 'https?://[A-Za-z0-9.-]+' "$SRC" 2>/dev/null \
    | sed -E 's#^https?://##' | sort -u)
host_count=$(printf '%s' "$hosts" | grep -c . )
process_count=$(hits 'Process(' "$SRC" | wc -l | tr -d ' ')
http_count=$(hits 'http://' "$SRC" | wc -l | tr -d ' ')

echo "network hosts (${host_count}): $(echo $hosts)"
echo "Process( call sites: ${process_count}"
echo "plain http:// hits: ${http_count}"

[ "$host_count" -gt 1 ] && { echo "FAIL: more than one network host"; status=1; }
[ "$process_count" -gt 1 ] && { echo "FAIL: more than one subprocess call site"; status=1; }
[ "$http_count" -gt 0 ] && { echo "FAIL: plain http:// in source"; status=1; }
if [ -f Package.swift ] && grep -q '\.package(' Package.swift; then
    echo "FAIL: Package.swift declares dependencies"; status=1
else
    echo "dependencies: none"
fi

[ "$status" -eq 0 ] && echo "RESULT: pass" || echo "RESULT: FAIL"
exit "$status"
