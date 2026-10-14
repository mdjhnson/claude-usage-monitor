#!/bin/bash
# Lists every security-relevant line in the app source so it can be reviewed in one sitting,
# then enforces the rules. Exits non-zero on any violation:
#   - the only host is api.anthropic.com, and networking lives only in UsageClient.swift
#   - the only subprocess is the one Process in KeychainTokenReader.swift
#   - no shells, exec/spawn, AppleScript, listeners, URL opening, or Keychain data/write APIs
#   - notifications use UserNotifications only (no deprecated NSUserNotification)
#   - the only app launch is Terminal.app, from the setup guide
#   - the only other URLs are Claude Code's installer, shown and copied by the setup guide, never fetched,
#     and the source repository, the one link in the app (About tab), opened in the default browser
#   - the only other URL opened is PaceBar's page in System Settings › Notifications (a fixed
#     x-apple.systempreferences: URL, from the Notifications tab), which opens locally
#   - Sources/ holds Swift only; Package.swift has no dependencies, binaries, plugins or flags
#   - the entitlements file grants exactly com.apple.security.network.client
set -u
cd "$(dirname "$0")/.." || exit 2

SRC="Sources"
TESTS="Tests"
RESOURCES="Resources"
CLIENT="Sources/PaceBarCore/UsageClient.swift"
READER="Sources/PaceBarCore/KeychainTokenReader.swift"
GUIDE="Sources/PaceBar/UI/SetupGuideView.swift"
TERMINAL_URL='URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")'
INSTALL_URL="https://claude.ai/install.sh"
ABOUT="Sources/PaceBar/UI/AboutView.swift"
REPO_URL="https://github.com/mdjhnson/claude-usage-monitor"
REPO_LINK='Link(Self.repository, destination: Self.repositoryURL)'
NOTIFIER="Sources/PaceBar/Notifier.swift"
SETTINGS_URL="x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.mdjhnson.pacebar"
SETTINGS_LINK='NSWorkspace.shared.open(Self.notificationSettingsURL)'
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
# Removes one allowed URL from one file's hits, so any other URL in that file still counts.
strip_url() {
    awk -v f="$1:" -v u="$2" \
        'index($0, f) == 1 { while ((i = index($0, u)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(u)) } { print }'
}
# The installer URL in the setup guide and the repository URL in the About tab.
strip_allowed_urls() { strip_url "$GUIDE" "$INSTALL_URL" | strip_url "$ABOUT" "$REPO_URL"; }

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
'NWListener|NWConnection|CFStream|NSUserNotification|'\
'NSAppleEventManager|handleGetURLEvent|WKWebView|openURL|(^|[^.A-Za-z0-9_])Link\(|NSWorkspace[^(]*\.open\(|'\
'FileManager.*\.claude|NSPasteboard.*[Tt]oken' "$SRC" | code_only \
    | awk -v f="$ABOUT:" -v l="$REPO_LINK" '!(index($0, f) == 1 && index($0, l) > 0)' \
    | awk -v f="$NOTIFIER:" -v l="$SETTINGS_LINK" '!(index($0, f) == 1 && index($0, l) > 0)')
if [ -n "$forbidden" ]; then echo "$forbidden"; fail "forbidden construct(s) above"; else echo "(none)"; fi

section "App launches"
launches=$(rhits 'openApplication|NSRunningApplication|LSOpen|launchApplication' "$SRC" | code_only)
echo "${launches:-(none)}"
if [ -n "$launches" ]; then
    stray=$(printf '%s\n' "$launches" | grep -vF "$GUIDE:" )
    [ -n "$stray" ] && fail "app launched outside SetupGuideView.swift"
    [ "$(printf '%s\n' "$launches" | grep -c .)" -gt 1 ] && fail "more than one app launch call site"
    printf '%s\n' "$launches" | grep -qF 'openApplication(at: Self.terminalURL,' || fail "the app launch must open Self.terminalURL"
    [ "$(grep -cF "terminalURL = $TERMINAL_URL" "$GUIDE")" -eq 1 ] || fail "terminalURL must be the fixed Terminal.app path"
fi

section "Links"
links=$(rhits '(^|[^.A-Za-z0-9_])Link\(|openURL|NSWorkspace[^(]*\.open\(' "$SRC" | code_only)
echo "${links:-(none)}"
stray_links=$(printf '%s\n' "$links" | grep . | outside "$ABOUT" | outside "$NOTIFIER")
[ -n "$stray_links" ] && fail "link opened outside AboutView.swift and Notifier.swift"
[ "$(printf '%s\n' "$links" | grep -c .)" -gt 2 ] && fail "more than two links"
about_links=$(printf '%s\n' "$links" | grep -F "$ABOUT:")
if [ -n "$about_links" ]; then
    [ "$(printf '%s\n' "$about_links" | grep -c .)" -gt 1 ] && fail "more than one link in AboutView.swift"
    printf '%s\n' "$about_links" | grep -qF "$REPO_LINK" || fail "the About link must be $REPO_LINK"
    [ "$(grep -cF "static let repositoryURL = URL(string: \"$REPO_URL\")!" "$ABOUT")" -eq 1 ] \
        || fail "repositoryURL must be the fixed repository address"
fi
notifier_links=$(printf '%s\n' "$links" | grep -F "$NOTIFIER:")
if [ -n "$notifier_links" ]; then
    [ "$(printf '%s\n' "$notifier_links" | grep -c .)" -gt 1 ] && fail "more than one link in Notifier.swift"
    printf '%s\n' "$notifier_links" | grep -qF "$SETTINGS_LINK" || fail "the Notifier link must be $SETTINGS_LINK"
    [ "$(grep -cF "static let notificationSettingsURL = URL(string: \"$SETTINGS_URL\")!" "$NOTIFIER")" -eq 1 ] \
        || fail "notificationSettingsURL must be the fixed System Settings address"
fi

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
hosts=$(rhits 'https?://' "$SRC" | code_only | strip_allowed_urls \
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
