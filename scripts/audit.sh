#!/bin/bash
# Lists every security-relevant line in the app source so it can be reviewed in one sitting,
# then enforces the rules. Exits non-zero on any violation:
#   - the hosts are api.anthropic.com and api.github.com, and networking lives only in UsageClient.swift
#     and UpdateClient.swift. api.github.com is one fixed URL in UpdateClient.swift, which has no
#     token, credential or Keychain code
#   - the only subprocess is the one Process in KeychainTokenReader.swift
#   - no shells, exec/spawn, AppleScript, listeners, URL opening, or Keychain data/write APIs
#   - notifications use UserNotifications only (no deprecated NSUserNotification)
#   - the only app launch is Terminal.app, from the setup guide
#   - the only other URLs are Claude Code's installer, shown and copied by the setup guide, never fetched,
#     and the source repository and PaceBar's staff download page, the About tab's two links,
#     opened in the default browser
#   - the only other URL opened is PaceBar's page in System Settings › Notifications (a fixed
#     x-apple.systempreferences: URL, from the Notifications tab), which opens locally
#   - Sources/ holds Swift only; Package.swift and project.yml have no dependencies, binaries,
#     plugins or flags
#   - the app's entitlements are exactly network.client plus the PaceBar App Group; the widget's
#     are exactly app-sandbox plus that group; Release builds carry no get-task-allow
#   - the only file written is the widget snapshot, from WidgetSnapshot.swift, the only code that
#     opens the App Group container
#   - the widget extension has no networking, subprocess, Keychain, notification or URL-opening code
#   - the only Darwin notification is the widgets' refresh request: posted only by RefreshIntent.swift,
#     observed only by WidgetPublisher.swift, named only by WidgetSnapshot.swift
set -u
cd "$(dirname "$0")/.." || exit 2

SRC="Sources"
TESTS="Tests"
RESOURCES="Resources"
CLIENT="Sources/PaceBarCore/UsageClient.swift"
UPDATER="Sources/PaceBarCore/UpdateClient.swift"
GITHUB_API_URL="https://api.github.com/repos/mdjhnson/claude-usage-monitor/releases/latest"
READER="Sources/PaceBarCore/KeychainTokenReader.swift"
GUIDE="Sources/PaceBar/UI/SetupGuideView.swift"
TERMINAL_URL='URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")'
INSTALL_URL="https://claude.ai/install.sh"
ABOUT="Sources/PaceBar/UI/AboutView.swift"
REPO_URL="https://github.com/mdjhnson/claude-usage-monitor"
REPO_LINK='Link(Self.repository, destination: Self.repositoryURL)'
DOWNLOAD_URL="https://staff-services.serve.campusoutreach.org/tools/pacebar"
DOWNLOAD_LINK='Link("Download", destination: Self.downloadURL)'
NOTIFIER="Sources/PaceBar/Notifier.swift"
WIDGET="Sources/PaceBarWidget"
SNAPSHOT="Sources/PaceBarCore/WidgetSnapshot.swift"
PUBLISHER="Sources/PaceBar/WidgetPublisher.swift"
REFRESH_INTENT="Sources/PaceBarWidget/RefreshIntent.swift"
APP_GROUP='$(TeamIdentifierPrefix)io.github.mdjhnson.pacebar'
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
# The installer URL in the setup guide and the repository and download URLs in the About tab.
strip_allowed_urls() {
    strip_url "$GUIDE" "$INSTALL_URL" | strip_url "$ABOUT" "$DOWNLOAD_URL" | strip_url "$ABOUT" "$REPO_URL"
}

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
    | awk -v f="$ABOUT:" -v l="$DOWNLOAD_LINK" '!(index($0, f) == 1 && index($0, l) > 0)' \
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
[ "$(printf '%s\n' "$links" | grep -c .)" -gt 3 ] && fail "more than three links"
about_links=$(printf '%s\n' "$links" | grep -F "$ABOUT:")
if [ -n "$about_links" ]; then
    [ "$(printf '%s\n' "$about_links" | grep -c .)" -gt 2 ] && fail "more than two links in AboutView.swift"
    [ -n "$(printf '%s\n' "$about_links" | grep -vF "$REPO_LINK" | grep -vF "$DOWNLOAD_LINK")" ] \
        && fail "the About links must be $REPO_LINK and $DOWNLOAD_LINK"
    [ "$(grep -cF "static let repositoryURL = URL(string: \"$REPO_URL\")!" "$ABOUT")" -eq 1 ] \
        || fail "repositoryURL must be the fixed repository address"
    [ "$(grep -cF "static let downloadURL = URL(string: \"$DOWNLOAD_URL\")!" "$ABOUT")" -eq 1 ] \
        || fail "downloadURL must be the fixed staff download page"
fi
notifier_links=$(printf '%s\n' "$links" | grep -F "$NOTIFIER:")
if [ -n "$notifier_links" ]; then
    [ "$(printf '%s\n' "$notifier_links" | grep -c .)" -gt 1 ] && fail "more than one link in Notifier.swift"
    printf '%s\n' "$notifier_links" | grep -qF "$SETTINGS_LINK" || fail "the Notifier link must be $SETTINGS_LINK"
    [ "$(grep -cF "static let notificationSettingsURL = URL(string: \"$SETTINGS_URL\")!" "$NOTIFIER")" -eq 1 ] \
        || fail "notificationSettingsURL must be the fixed System Settings address"
fi

section "Networking outside $CLIENT and $UPDATER"
net=$(rhits 'URLSession|URLRequest\(|URLComponents|\.host *=' "$SRC" | code_only | outside "$CLIENT" | outside "$UPDATER")
if [ -n "$net" ]; then echo "$net"; fail "networking APIs used outside UsageClient.swift and UpdateClient.swift"; else echo "(none)"; fi

section "Update check  [$UPDATER]"
github=$(rhits 'https?://api\.github\.com' "$SRC" | code_only)
echo "${github:-(none)}"
[ -n "$(printf '%s' "$github" | grep . | outside "$UPDATER")" ] && fail "api.github.com URL outside UpdateClient.swift"
[ "$(grep -cF "static let latestURL = URL(string: \"$GITHUB_API_URL\")!" "$UPDATER")" -eq 1 ] \
    || fail "latestURL must be the fixed latest-release API address"
[ "$(grep -nH 'https://' "$UPDATER" | code_only | grep -c .)" -eq 1 ] || fail "UpdateClient.swift may hold only the one latestURL"
updater_secrets=$(grep -nHE 'Authorization|OAuthCredential|accessToken|KeychainTokenReader|SecItem|UserDefaults' "$UPDATER" | code_only)
if [ -n "$updater_secrets" ]; then
    echo "$updater_secrets"; fail "UpdateClient.swift must not touch credentials, the Keychain or settings"
else
    echo "no credentials, Keychain or settings in the update client"
fi

section "Subprocess call sites"
procs=$(rhits '\bProcess\b' "$SRC" | code_only)
echo "${procs:-(none)}"
process_count=$(printf '%s' "$procs" | grep -c .)
stray=$(printf '%s' "$procs" | grep . | outside "$READER")
[ -n "$stray" ] && fail "Process used outside KeychainTokenReader.swift"
[ "$process_count" -gt 1 ] && fail "more than one Process call site"

section "File writes and the App Group container"
writes=$(rhits '\.write\(to:|createFile\(|FileHandle\(forWriting|fopen\(|containerURL\(' "$SRC" | code_only)
echo "${writes:-(none)}"
stray_writes=$(printf '%s' "$writes" | grep . | outside "$SNAPSHOT")
[ -n "$stray_writes" ] && fail "file written or App Group container opened outside WidgetSnapshot.swift"

section "Darwin notifications (the widgets' refresh request)"
darwin=$(rhits 'CFNotificationCenter|notify_post|notify_register|DistributedNotificationCenter' "$SRC" | code_only)
echo "${darwin:-(none)}"
[ -n "$(printf '%s' "$darwin" | grep . | outside "$PUBLISHER" | outside "$REFRESH_INTENT")" ] \
    && fail "Darwin or distributed notifications outside WidgetPublisher.swift and RefreshIntent.swift"
printf '%s' "$darwin" | grep -F "$PUBLISHER:" | grep -q 'Post' && fail "the app must only observe the refresh request"
printf '%s' "$darwin" | grep -F "$REFRESH_INTENT:" | grep -q 'AddObserver' && fail "the widget must only post the refresh request"
[ -n "$(rhits 'refreshNotificationName\(' "$SRC" | code_only | grep -v 'refreshNotificationName()' | outside "$SNAPSHOT")" ] \
    && fail "the refresh notification name is built outside WidgetSnapshot.swift"

section "Widget extension  [$WIDGET]"
widget_forbidden=$(rhits 'URLSession|URLRequest|\bProcess\b|SecItem|SecKeychain|UsageClient|UpdateClient|KeychainTokenReader|UNUserNotification|NSWorkspace|openURL|Link\(' "$WIDGET" | code_only)
if [ -n "$widget_forbidden" ]; then
    echo "$widget_forbidden"; fail "networking, subprocess, Keychain, notification or URL code in the widget"
else
    echo "(none)"
fi

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
    # Keys, sorted, and every string value, which must all be the one App Group.
    ent_keys() { grep -o '<key>[^<]*</key>' "$1" | sed 's/<[^>]*>//g' | sort | paste -sd ' ' -; }
    ent_strings() { grep -o '<string>[^<]*</string>' "$1" | sed 's/<[^>]*>//g' | sort -u; }
    files=$(ls "$RESOURCES"/*.entitlements 2>/dev/null | paste -sd ' ' -)
    echo "entitlements files: $files"
    [ "$files" = "$RESOURCES/PaceBar.entitlements $RESOURCES/PaceBarWidget.entitlements" ] \
        || fail "expected exactly PaceBar.entitlements and PaceBarWidget.entitlements"
    for f in "$RESOURCES/PaceBar.entitlements" "$RESOURCES/PaceBarWidget.entitlements"; do
        echo "$f: $(ent_keys "$f")"
        echo "  groups: $(ent_strings "$f")"
        [ "$(ent_strings "$f")" = "$APP_GROUP" ] || fail "$f: the only App Group must be $APP_GROUP"
    done
    [ "$(ent_keys "$RESOURCES/PaceBar.entitlements")" = "com.apple.security.application-groups com.apple.security.network.client" ] \
        || fail "app entitlements must be exactly network.client and application-groups"
    [ "$(ent_keys "$RESOURCES/PaceBarWidget.entitlements")" = "com.apple.security.app-sandbox com.apple.security.application-groups" ] \
        || fail "widget entitlements must be exactly app-sandbox and application-groups"
    grep -A1 'com.apple.security.app-sandbox' "$RESOURCES/PaceBarWidget.entitlements" | grep -q '<true/>' \
        || fail "the widget must be sandboxed"
fi

section "Xcode project  [project.yml]"
if grep -qE '^packages:|^ *- (package|framework|carthage):|OTHER_LDFLAGS|OTHER_SWIFT_FLAGS' project.yml; then
    fail "project.yml declares packages, prebuilt frameworks or extra flags"
else
    echo "dependencies: system SDKs only"
fi
grep -qE '^ *CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO' project.yml \
    || fail "Release builds must not inject get-task-allow (CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO)"
grep -q 'XCRemoteSwiftPackageReference' PaceBar.xcodeproj/project.pbxproj \
    && fail "PaceBar.xcodeproj references a remote package; regenerate it from project.yml"

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

# Every literal URL must be api.anthropic.com or api.github.com (an empty host means it is built
# at runtime).
stray_hosts=$(printf '%s\n' "$hosts" | grep . | grep -vxF 'api.anthropic.com' | grep -vxF 'api.github.com')
[ -n "$stray_hosts" ] && fail "unexpected network host(s): $(echo $stray_hosts)"
[ "$http_count" -gt 0 ] && fail "plain http:// in source"
if grep -qE '\.package\(|binaryTarget|\.plugin\(|unsafeFlags|linkedLibrary|linkedFramework' Package.swift; then
    fail "Package.swift declares dependencies, binaries, plugins or unsafe/linker settings"
else
    echo "dependencies: none"
fi

[ "$status" -eq 0 ] && echo "RESULT: pass" || echo "RESULT: FAIL"
exit "$status"
