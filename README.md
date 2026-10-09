# PaceBar

A small macOS menu bar app that shows your Claude usage limits and whether you are spending them faster or slower than a steady pace. Its look follows [TokenEater](https://github.com/AThevon/TokenEater), with a code base small enough to audit in one sitting: about 2,500 lines of Swift (plus about 900 lines of tests), with no dependencies.

- **Menu bar:** live percentages for the windows you choose (default: 5-hour session and weekly), colored by pacing zone or by usage thresholds.
- **Popover:** one card per window, each showing:
  - the percentage and reset countdown
  - a pacing bar (fill = actual usage, triangle = expected pace)
  - a zone pill with the signed delta ("On track +7%") and a one-line quip
  - when you're past the on-track band (Watch out or Hot), roughly when you'll be back on pace
- **Workweek pacing (optional):** weekly limits pace over your active days and hours only. Weekends and evenings don't count against you.

## How pacing works

For each window with a reset time:

```
start     = resetsAt − duration            (5 h session, 7 d weekly)
expected  = elapsed fraction × 100
delta     = utilization − expected
```

With margin `m` (default 10, adjustable 5–20):

| Zone | Condition |
|---|---|
| Chill | `delta < −m` |
| On track | `−m ≤ delta ≤ m` |
| Watch out | `m < delta ≤ 2m` |
| Hot | `delta > 2m` |

**Workweek pacing** (weekly windows only) counts only active seconds. Elapsed is `activeSeconds(start, now) / activeSeconds(start, resetsAt)`. Day boundaries come from the calendar, so DST days of 23 or 25 hours stay exact.

**"Back on pace around …"** is when the pace line catches up with your current usage if you stop now. It shows only in the Watch out and Hot zones. In workweek mode it walks forward through active time only, and it is never later than the reset.

The pure logic lives in `Sources/PaceBarCore` and is covered by unit tests.

## Requirements

- macOS 14 or later.
- **Toolchain:** Xcode 27.0 (build 27A266a), Swift 6.4 (swiftlang-6.4.0.34.1). It's pinned here because no other build configuration is tested. The scripts use Xcode through `DEVELOPER_DIR`, so `xcode-select` can stay pointed at the Command Line Tools. Accept the Xcode license once, either by launching Xcode or with `sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license accept`.
- Claude Code installed and signed in (`claude`, then `/login`).

## Build, test, run

```sh
./test.sh                 # all unit tests
./scripts/audit.sh        # security review listing; exits non-zero on a violation
./build.sh                # Release build → build/PaceBar.app (ad hoc signed, hardened runtime)
open build/PaceBar.app
```

To sign with your development identity instead of ad hoc: `SIGN_ID="Apple Development: Your Name (TEAMID)" ./build.sh`.

There is no `Package.resolved`. SwiftPM only writes one when a package has dependencies, and PaceBar has none. `audit.sh` fails if any appear.

### First launch

1. If Gatekeeper blocks the app, right-click `PaceBar.app`, choose **Open**, then **Open** again. A copy built on your own Mac normally isn't quarantined, so this is rare.
2. macOS asks whether `security` may access the "Claude Code-credentials" Keychain item. Choose **Always Allow**. If you click **Allow** instead, you'll be asked again on every refresh. The first read after launch waits up to 60 seconds for your answer.
   - If no prompt appears, `security` already has access. Another tool that reads Claude Code's login the same way (TokenEater, for example) granted it earlier. The ACL caveat below then already applies.
3. The menu bar shows something like `5h 42%  7d 18%`. Click it for the dashboard.

**Menu bar managers (Bartender, Ice):** PaceBar's status item has a fixed autosave name (`io.github.mdjhnson.pacebar.status`), so these tools remember where you put it across launches and rebuilds. In their item lists it appears with the PaceBar icon, a small pacing bar on a dark tile.

The item is drawn lazily. Its label gray follows the menu bar when macOS switches between light and dark menu bar text, for example with a rotating wallpaper. Theme colors stay fixed. If they're hard to read on your wallpaper, try the Pill style or Monochrome.

To move the app, copy `build/PaceBar.app` to `/Applications`. Launch at login works from anywhere, but `/Applications` is the conventional place.

## Settings

Open Settings from the gear in the popover. Settings are split into four tabs: Pacing, Menu Bar, Appearance and General.

| Setting | Default | Notes |
|---|---|---|
| Margin | ±10% | 5–20. The width of the "On track" band. |
| Workweek pacing | Off | Active days (default Mon–Fri) and optional active hours (default 9 AM–6 PM, local time). Applies to weekly limits only. |
| Windows | Menu bar: 5-hour, Weekly. Popover: all | For each limit, choose whether it appears in the menu bar and in the popover. Per-model weekly limits (for example Fable) appear here once the API reports them. |
| Menu bar style | Classic | Classic (label plus colored value) or Pill. |
| Color by | Pacing zone | Or Usage threshold. Windows without a reset time always use thresholds. |
| Monochrome menu bar | Off | Draws in the system label color. |
| Theme | Default | Default, Monochrome, Neon, Pastel. These are TokenEater's presets. |
| Warning / Critical at | 60% / 85% | Used for threshold coloring. |
| Refresh every | 3 min | 60–600 s. Opening the popover also refreshes, at most once per 30 s. |
| Launch at login | Off | Uses `SMAppService.mainApp`. macOS may ask you to approve it in Login Items. |
| Copy diagnostic | — | Copies a redacted report (see below). |

## Threat model and security design

PaceBar holds a **full-scope Claude Code OAuth token** in memory while a request is in flight. Anyone who obtains that token can act as your Claude account. The design aims to keep the token's exposure as small as practical.

### What the app does with the token

- It reads the token from the macOS Keychain on every refresh, uses it for one HTTPS request, then drops it. The token is never cached between refreshes.
- It never writes, modifies or refreshes any credential. If the token has expired, the app asks you to open Claude Code so it can refresh its own login.
- The token is never written to disk, `UserDefaults`, logs, the pasteboard or any cache. It never appears in a command-line argument, environment variable or URL.
  - Its type redacts itself in every `description`, `debugDescription` and `Mirror`, so it can't be printed by accident.
- **Limitation:** Swift `String` storage can't be reliably zeroed, so freed memory may still hold the token until it is reused. A process that can read PaceBar's memory can already do much worse.

### Network

- **One host:** `https://api.anthropic.com/api/oauth/usage`. There is no analytics, telemetry, update check or crash reporting.
- The request URL is checked right before sending: https only, exact host `api.anthropic.com`, default port, no user info. The response URL is checked again.
- **Every redirect is refused,** including same-host redirects.
- The session is ephemeral, with no cookie store, URL cache or credential storage. TLS 1.2 is the minimum.
- `os.Logger` records status codes and error kinds only. Headers and bodies are never logged.

### Subprocess and Keychain

- The only subprocess is `/usr/bin/security find-generic-password -s "Claude Code-credentials" -a <account> -w`.
  - It uses an absolute path and fixed arguments, with no shell.
  - Its environment contains only `HOME`.
  - Its stdout is drained concurrently, and it is killed (SIGTERM, then SIGKILL) if it doesn't finish in time.
- Accounts are found with `SecItemCopyMatching` asking for **attributes only**, which never shows a prompt. `kSecReturnData` is never used.
- If several items exist (for example, a "shadowing" item without OAuth data), the one with the latest `expiresAt` wins.
- **The ACL caveat:** when you choose **Always Allow**, the Keychain item's access list gains `/usr/bin/security`, not PaceBar.
  - From then on, **any process running as your user can read the Claude Code token by running the same command, without a prompt.**
  - This is inherent to reading another app's Keychain item through `security`. Assume the token can be read by anything that runs as you.
  - To undo it, open Keychain Access, find "Claude Code-credentials", and remove `security` from Access Control.

### Process hardening

- **Not sandboxed.** An App Sandbox would prevent running `/usr/bin/security` to read another app's Keychain item, which is the only way PaceBar gets the token.
- **Hardened runtime is on.** The only entitlement is `com.apple.security.network.client`. There are no library-validation or JIT exceptions.
- There are no listening sockets, no URL scheme handlers, no AppleScript, and no files written into `~/.claude`.
- **No auto-update.** You update by pulling and rebuilding.

### Failure behavior

On any error, the last good data stays on screen, dimmed, with "Last updated N min ago" and a short message.
- Malformed responses never crash the app. Unknown keys are ignored and a broken bucket is dropped individually.
- **HTTP 429:**
  - `Retry-After` is honored, whether sent as seconds or as an HTTP date, up to a one-hour sanity bound.
  - Without the header, the wait doubles from the refresh interval each time, capped at 15 minutes.
  - Waking the Mac doesn't skip a running backoff.
- **Keychain timeouts:** background refreshes allow the `security` call 3 seconds (on recent macOS it can hang when launched from a menu bar app). The first read after launch, and any read you start with Retry, allow 60 seconds, so there's time to answer the macOS prompt.
- **Keychain denial:** if you deny access, background refreshes stop asking until you click Retry.

### Auditing

`./scripts/audit.sh` lists every line in `Sources/` containing `http://`, `https://`, `Process(`, `URLSession`, `UserDefaults`, `print(` or `NSLog(`. It then checks for:
- forbidden constructs: data-returning or writing Keychain calls, shells, AppleScript, listeners
- URL schemes in Info.plist
- extra entitlements
- package dependencies

It prints a summary with the network hosts and subprocess call sites.

## Copy diagnostic

Settings › Copy diagnostic copies a plain-text report.

**It includes:**
- app and macOS versions
- the number of Keychain items under the service
- whether a token was found, and its expiry relative to now
- the last HTTP status and error kind
- the refresh interval and backoff state
- the response's **shape**: every key path with its JSON type. Only `kind`, `group` and model `display_name` show their values, because they name limit types and models. Dates show their format only.

**It never includes:** the token, account names, email addresses, IDs (keys that look like identifiers are replaced with `<id>`), or usage numbers.

## Data source notes

The usage endpoint is undocumented, so PaceBar decodes it tolerantly:
- Buckets are `{ utilization, resets_at }`. `resets_at` may have any number of fractional-second digits (the API sends 6) or be null.
- On migrated accounts, a `limits[]` array uses `percent` and `kind` (`session`, `weekly_all`, `weekly_scoped` plus `scope.model.display_name`).
- Each limit is taken from the flat key when that key has a reset time. Otherwise it comes from the matching `limits[]` entry.
- A bad `limits[]` element is skipped on its own rather than dropping the whole array.
- `extra_usage`, `spend`, `weekly_scoped_shares`, per-limit `severity`, per-bucket dollar fields, and other unknown keys (including many code-named null keys) are ignored.

`Tests/PaceBarCoreTests/RealShapeFixtureTests.swift` mirrors a real response shape captured with Copy diagnostic on 2026-10-09. It uses the real key names and types, with invented values.

A window without a reset time shows its percentage but no pacing.

## Design notes

[DESIGN_NOTES.md](DESIGN_NOTES.md) has the exact visual spec. One difference from TokenEater's website is deliberate:
- **The website** shows the "On track" pill in amber, on a fixed green-to-amber bar.
- **The app source** colors "On track" blue (`#0A84FF`) in its default theme, uses amber (`#FF9500`) for the "Watch out" zone, and colors the whole bar by the current zone.
- **PaceBar** follows the app source.

## Uninstall

1. If you turned on Launch at login, turn it off in Settings first, or remove PaceBar later in System Settings › General › Login Items.
2. Quit PaceBar (popover › Quit), then delete `PaceBar.app`.
3. Remove its preferences: `defaults delete io.github.mdjhnson.pacebar`.
4. Optional: in Keychain Access, open "Claude Code-credentials" › Access Control and remove `security` if you don't want other tools to keep prompt-free access.

PaceBar writes nothing else to disk.

## Not implemented

These are out of scope for v1. The code has clean seams for them, but none are built:
- Codex or other provider tracking
- usage history or session-log parsing
- agent watchers
- desktop widgets (WidgetKit)
- notifications (if added, they must use `UserNotifications` only)
- extra-credits (`extra_usage`) display

Also not done:
- **User-Agent version detection.** The app sends `claude-code/0.0.0`. If the endpoint starts rejecting that, add version detection from file metadata, with no shell.
- **Universal binary.** `build.sh` builds for the host architecture only.
- **Notarization.** The app is ad hoc or development signed, for personal use.
- **Localization.** English only.

## License

MIT. See [LICENSE](LICENSE).

## Credits

The pacing model, quips, theme presets and visual design follow TokenEater by AThevon (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
