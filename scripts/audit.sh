#!/bin/bash
# Lists every security-relevant line in the app source so it can be reviewed in one sitting,
# then enforces the rules. Exits non-zero on any violation:
#   - the only host is api.anthropic.com, and networking lives only in UsageClient.swift
#   - the only subprocess is the one Process in KeychainTokenReader.swift
#   - no shells, exec/spawn, AppleScript, listeners, URL opening, or Keychain data/write APIs
#   - Sources/ holds Swift only; Package.swift has no dependencies, binaries, plugins or flags
#   - the entitlements file grants exactly com.apple.security.network.client
set -u
cd "$(dirname "$0")/.." || exit 2

SRC="Sources"
TESTS="Tests"
RESOURCES="Resources"
CLIENT="Sources/PaceBarCore/UsageClient.swift"
READER="Sources/PaceBarCore/KeychainTokenReader.swift"
status=0

section() { printf '\n== %s ==\n' "$1"; }
fail() { echo "FAIL: $1"; status=1; }
# Fixed-string and regex searches over every file in a directory, as "file:line:text".
hits() { grep -rnF -- "$1" "$2" 2>/dev/null; }
rhits() { grep -rnE -- "$1" "$2" 2>/dev/null; }
# Drops hits whose code is only a comment. Used for enforcement; listings show everything.
code_only() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'; }
# Hits outside one allowed file.
outside() { grep -v "^$1:"; }

echo "PaceBar source audit ($(date '+%Y-%m-%d %H:%M'))"

for pattern in 'http://' 'https://' 'Process' 'URLSession' 'UserDefaults' 'print(' 'NSLog('; do
    section "$pattern  [Sources]"
    hits "$pattern" "$SRC" || echo "(none)"
done

section "Forbidden constructs  [Sources]"
forbidden=$(rhits \
'kSecReturnData|"r_Data"|SecItemAdd|SecItemUpdate|SecItemDelete|SecItemExport|SecKeychainFindGenericPassword|SecKeychainItemCopyContent|SecKeychainAdd|'\
'osascript|NSAppleScript|OSAScript|NSUserUnixTask|NSUserAppleScriptTask|/bin/(ba|z)?sh|launchPath|'\
'posix_spawn|execv|execl|(^|[^.A-Za-z0-9_])(popen|system|dlopen|bind|listen|socket)\(|'\
'NWListener|NWConnection|CFStream|'\
'NSAppleEventManager|handleGetURLEvent|WKWebView|openURL|(^|[^.A-Za-z0-9_])Link\(|NSWorkspace[^(]*\.open(Application)?\(|'\
'FileManager.*\.claude|NSPasteboard.*[Tt]oken' "$SRC" | code_only)
if [ -n "$forbidden" ]; then echo "$forbidden"; fail "forbidden construct(s) above"; else echo "(none)"; fi

section "Networking outside $CLIENT"
net=$(rhits 'URLSession|URLRequest\(|URLComponents|\.host *=' "$SRC" | code_only | outside "$CLIENT")
if [ -n "$net" ]; then echo "$net"; fail "networking APIs used outside UsageClient.swift"; else echo "(none)"; fi

section "Subprocess call sites"
procs=$(rhits '\bProcess\b' "$SRC" | code_only)
echo "${procs:-(none)}"
process_count=$(printf '%s' "$procs" | grep -c .)
stray=$(printf '%s' "$procs" | grep . | outside "$READER")
[ -n "$stray" ] && fail "Process used outside KeychainTokenReader.swift"
[ "$process_count" -gt 1 ] && fail "more than one Process call site"

section "Non-Swift files in Sources"
others=$(find "$SRC" -type f ! -name '*.swift')
if [ -n "$others" ]; then echo "$others"; fail "non-Swift sources are not covered by this audit"; else echo "(none)"; fi

if [ -d "$RESOURCES" ]; then
    section "Bundle configuration  [Resources]"
    if grep -q 'CFBundleURLTypes\|CFBundleDocumentTypes\|NSServices' "$RESOURCES"/*.plist 2>/dev/null; then
        fail "URL scheme, document type or service declared"
    else
        echo "no URL schemes, document types or services"
    fi
    keys=$(grep -ho '<key>[^<]*</key>' "$RESOURCES"/*.entitlements 2>/dev/null | sed 's/<[^>]*>//g')
    echo "entitlements:"
    echo "$keys" | sed 's/^/  /'
    [ "$keys" = "com.apple.security.network.client" ] || fail "entitlements must be exactly com.apple.security.network.client"
fi

section "Tests (informational: stubbed sessions and fixtures live here)"
for pattern in 'https://' 'URLSession' 'Process' 'UserDefaults'; do
    count=$(hits "$pattern" "$TESTS" | wc -l | tr -d ' ')
    printf '%-14s %s hit(s)\n' "$pattern" "$count"
done

section "Summary"
hosts=$(rhits 'https?://' "$SRC" | code_only \
    | grep -oE 'https?://[A-Za-z0-9.-]*' | sed -E 's#^https?://##; s#\.+$##' | sort -u)
host_count=$(printf '%s' "$hosts" | grep -c .)
http_count=$(hits 'http://' "$SRC" | code_only | wc -l | tr -d ' ')

echo "network hosts (${host_count}): $(echo $hosts)"
echo "Process call sites: ${process_count}"
echo "plain http:// hits: ${http_count}"

# Every literal URL must be exactly api.anthropic.com (an empty host means it is built at runtime).
if [ -n "$hosts" ] && [ "$hosts" != "api.anthropic.com" ]; then fail "unexpected network host(s)"; fi
[ "$http_count" -gt 0 ] && fail "plain http:// in source"
if grep -qE '\.package\(|binaryTarget|\.plugin\(|unsafeFlags|linkedLibrary|linkedFramework' Package.swift; then
    fail "Package.swift declares dependencies, binaries, plugins or unsafe/linker settings"
else
    echo "dependencies: none"
fi

[ "$status" -eq 0 ] && echo "RESULT: pass" || echo "RESULT: FAIL"
exit "$status"
