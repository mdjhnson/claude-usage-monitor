# PaceBar

A small macOS menu bar app that shows your Claude usage limits and whether you are spending them faster or slower than a steady pace. Its look follows [TokenEater](https://github.com/AThevon/TokenEater), with a code base small enough to audit in one sitting: about 4,900 lines of Swift (plus about 1,500 lines of tests), with no dependencies.

- **Menu bar:** live percentages for the windows you choose (default: 5-hour session and weekly), colored by pacing zone or by usage thresholds.
- **Popover:** one card per window, each showing:
  - the percentage and reset countdown
  - a pacing bar (fill = actual usage, triangle = expected pace)
  - a zone pill with the signed delta ("On track +7%") and a one-line quip
  - when you're past the on-track band (Watch out or Hot), roughly when you'll be back on pace
  - a usage graph: this cycle's readings against the steady-pace line, so a slow start and a late ramp show their real shape. Hover it to see any reading's time and usage, and where the pace line was then.
- **Workweek pacing (optional):** weekly limits pace over your active days and hours only. Weekends and evenings don't count against you.
- **Notifications (optional, off by default):** usage alerts at your thresholds, running hot and back on pace, and reminders before a reset.
- **Widgets:** small, medium and large widgets for the desktop and Notification Center, with the same colors, pacing and graphs as the popover (see **Widgets** below).

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
- Claude Code installed and signed in (`claude`, then `/login`). If it isn't, the popover walks you through it (see **Setup guide** below). The Claude desktop app's sign-in isn't enough on its own: it doesn't store a login PaceBar can read.

## Build, test, run

```sh
./test.sh                 # all unit tests
./scripts/audit.sh        # security review listing; exits non-zero on a violation
./build.sh                # Release build → build/PaceBar.app (Apple Development signed, hardened runtime)
open build/PaceBar.app
./deploy.sh               # build, quit the running copy, install to /Applications and relaunch
```

**Signing needs an Apple Development certificate.** The app and its widget share an App Group named after your team (`<team ID>.io.github.mdjhnson.pacebar`), and macOS only lets them use it when both are signed by that team, so an ad hoc build can't run the widget.
- Any team works for a local build, including the free Personal Team you get by signing in to Xcode › Settings › Accounts. To create the certificate, choose Manage Certificates › + › Apple Development.
- `build.sh` uses your certificate's team. If you have certificates for more than one team, pick one with `TEAM_ID=… ./build.sh`. If you name a team you have no certificate for, it says which teams you do have.
- You don't need a development certificate for the team you release with. `release.sh` builds ad hoc (`SIGN_ID=-`) for that team, and Xcode re-signs the build with the team's cloud-managed Developer ID.

Builds are universal (Apple silicon and Intel).

**Build numbers.** macOS caches each app's list of widgets and re-reads it only when the build number changes. Without a new number, a changed widget shows up blank or out of date in the gallery. So `deploy.sh` gives every local install its own `CFBundleVersion`: Info.plist's number plus a timestamp, for example `1.2610141708`. It also restarts the widget extension, which macOS would otherwise keep running with the old code. Releases use Info.plist's number unchanged.

**Project layout.** `PaceBar.xcodeproj` builds the app, the widget extension and `PaceBarCore`. It's generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so building doesn't need XcodeGen. After changing `project.yml`, run `xcodegen` and commit both. `Package.swift` builds the same `PaceBarCore` sources for `swift test`.

There is no `Package.resolved`. SwiftPM only writes one when a package has dependencies, and PaceBar has none. `audit.sh` fails if any appear, in `Package.swift` or `project.yml`.

### First launch

If you were given a DMG, open it and drag **PaceBar** into **Applications**, then open it from there. The DMG built by `release.sh` is notarized, so it opens without a warning.

1. If Gatekeeper blocks an unnotarized copy (one built with `build.sh` and sent to another Mac), click **Done**, then go to System Settings › Privacy & Security, scroll to the message about PaceBar and click **Open Anyway**. Right-click › Open no longer bypasses Gatekeeper on current macOS. A copy built on your own Mac normally isn't quarantined, so this is rare.
2. macOS asks whether `security` may access the "Claude Code-credentials" Keychain item. Choose **Always Allow**. If you click **Allow** instead, you'll be asked again on every refresh. The first read after launch waits up to 60 seconds for your answer.
   - If no prompt appears, `security` already has access. Another tool that reads Claude Code's login the same way (TokenEater, for example) granted it earlier. The ACL caveat below then already applies.
3. The menu bar shows something like `5h 42%  7d 18%`. Click it for the dashboard.

Opening the popover brings PaceBar to the front, so the usual shortcuts apply to it rather than to the app you were in: ⌘Q quits PaceBar, ⌘, opens Settings, ⌘W closes Settings, and ⌘C copies selected text.

### Setup guide

When there's no Claude Code login, or it has expired, the popover shows step-by-step instructions instead of an error. This is meant for people who use the Claude desktop app but have never used Claude Code.
- **Copy & Open Terminal** puts one command on the clipboard and opens Terminal.app. On a Mac without Claude Code, the command is `curl -fsSL https://claude.ai/install.sh | bash && ~/.local/bin/claude`, which installs Claude Code with Anthropic's installer and then starts it. If Claude Code is already installed, the command just starts it. The command is shown in the popover, so it's never hidden from the person running it.
- The person pastes it with ⌘V, signs in through Claude Code's prompts, and answers the Keychain prompt with **Always Allow**.
- To renew an expired login, they start Claude Code and run `/usage`, which makes Claude Code refresh its token.
- While the guide is showing, PaceBar checks the Keychain every 5 seconds and continues on its own. These checks never touch the network until a valid login exists.

PaceBar never runs the command itself and never types into Terminal.

**Menu bar managers (Bartender, Ice):** PaceBar's status item has a fixed autosave name (`io.github.mdjhnson.pacebar.status`), so these tools remember where you put it across launches and rebuilds. In their item lists it appears with the PaceBar icon, a small pacing bar on a dark tile.

The item is drawn lazily. Its label color follows the menu bar when macOS switches between light and dark menu bar text, for example with a rotating wallpaper. Theme colors stay fixed. If they're hard to read on your wallpaper, try the Pill style or Monochrome.

To move the app, run `./deploy.sh` or copy `build/PaceBar.app` to `/Applications`. Launch at login works from anywhere, but `/Applications` is the conventional place.

## Distributing to others

`./release.sh` builds a universal app, has Xcode sign it with your team's cloud-managed Developer ID certificate and notarize it, and packages the stapled app as `dist/PaceBar-<version>.dmg`. Anyone can open that DMG without Gatekeeper warnings. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` before each release.

```sh
TEAM_ID=ABCDE12345 ./release.sh
```

For each release:

1. `git checkout main && git pull`, so the build includes everything merged on GitHub.
2. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist` and commit it. Settings › About shows the commit a build came from, marked `-dirty` if the tree had uncommitted changes, so release from a clean tree.
3. `PUBLISH=1 TEAM_ID=<your team ID> ./release.sh`. With `PUBLISH=1`, the script finishes by publishing the DMG as GitHub Release `v<version>` (`gh release create … --generate-notes`), which is what **Check for Updates** reads. Before it builds, it checks that `gh` is signed in, the tree is clean, the commit is pushed and the tag is new, then tags exactly that commit. Without `PUBLISH=1`, it prints the `gh` command to run later.

The export signs the app and the widget extension. The first release after the widget was added may take a little longer while Xcode registers the widget's bundle ID (`io.github.mdjhnson.pacebar.widget`) for the team.

`DEPLOYMENT_COMMANDS.md` is gitignored, so you can keep your filled-in release command there.

One-time setup:

1. **Team access.** In App Store Connect › Users and Access, your user needs **Access to Certificates, Identifiers & Profiles** and **Access to Cloud Managed Developer ID Certificate**. The Account Holder or an Admin can turn these on. You don't need the Account Holder role, and you don't need a Developer ID certificate in your keychain: Apple holds the certificate and Xcode signs with it.
2. **Xcode account.** Sign in to that Apple Account in Xcode › Settings › Accounts. `release.sh` uses this account to sign and to notarize, so there's no app-specific password to set up.

Your team ID is in the top right of the Certificates, Identifiers & Profiles page, after the team name.

Notarization usually takes a minute or two. The script waits up to 30 minutes. The first time a team uses its cloud-managed Developer ID certificate, Apple may email the Account Holder about it.

The DMG itself isn't signed, because the cloud certificate only signs through Xcode, and Xcode signs the app, not the disk image. That doesn't cause a warning: Gatekeeper checks the app when it's opened, and the app carries its notarization ticket, so it opens offline too.

People who install it still go through **First launch** step 2. The Keychain prompt is about `/usr/bin/security`, not PaceBar, so signing doesn't change it.

## Settings

Open Settings from the gear in the popover. Settings are split into six tabs: Pacing, Menu Bar, Appearance, Notifications, General and About. About shows the version, build number and source commit (written in at build time), the update check, the author, a link to this repository, and credits.

| Setting | Default | Notes |
|---|---|---|
| Margin | ±10% | 5–20. The width of the "On track" band. |
| Workweek pacing | Off | Active days (default Mon–Fri) and optional active hours (default 9 AM–6 PM, local time). Applies to weekly limits only. |
| Windows | Menu bar: 5-hour, Weekly. Popover: all | For each limit, choose whether it appears in the menu bar and in the popover. Widgets show the popover's limits. Per-model weekly limits (for example Fable) appear here once the API reports them. |
| Menu bar style | Classic | Classic (label plus colored value) or Pill. |
| Color by | Pacing zone | Or Usage threshold. Windows without a reset time always use thresholds. |
| After each value | Nothing | **Reset countdown** (`1h25m`, `3d 4h`), **Pace arrows** (˅ under pace, ˄ ahead, double ˄ when Hot), or **Fire & ice** (❄ running cold, a flame outline for Watch out, a filled flame when Hot). Nothing shows while on track. |
| Monochrome menu bar | Off | Draws in the system label color. |
| Usage graph on each card | On | Plots readings since launch against the pace line. Kept in memory, so it starts fresh when PaceBar launches; the stretch from the window's start to the first reading is dashed. A copy of up to 120 readings per limit goes to the widget (see **Widgets**). Also controls the widget graphs. |
| Days on weekly graphs | Lines and day names | Off, Lines, or Lines and day names. Faint lines at each local midnight split weekly graphs into days; names sit underneath, with today's brighter. |
| Theme | Default | Default, Monochrome, Neon, Pastel (TokenEater's presets), or Custom. |
| Custom colors | The theme you switched from | Shown when Theme is Custom. Set any of the nine colors (four pacing zones, three usage thresholds, popover background and text) with a hex code (`#0A84FF` or `#08F`) or the system color picker. "Start from" copies a preset. A warning appears when text contrast drops below 4.5:1. |
| Warning / Critical at | 60% / 85% | Used for threshold coloring. |
| Usage alerts | Off | Notifies once per reset cycle when a limit passes the Warning and then the Critical threshold, with when it resets. |
| Running hot and back on pace | Off | Notifies when a limit enters the Hot zone, with roughly when you'd be back on pace if you ease off. Notifies again when it's back on track or under pace. |
| Before the session resets / weekly reset | Off | A reminder 5–60 min before the 5-hour session resets, or 30 min–6 hours before the weekly reset. |
| Refresh every | 3 min | 60–600 s. Opening the popover also refreshes, at most once per 30 s. |
| Launch at login | Off | Uses `SMAppService.mainApp`. macOS may ask you to approve it in Login Items. |
| Copy diagnostic | — | Copies a redacted report (see below). |
| Check for Updates | — | In About. Asks GitHub for the latest release's version and compares it with this build. If it's newer, About shows a Download link to the release page and the popover shows "PaceBar x.y.z is available". It never downloads or installs anything. See **Network**. |
| Check automatically once a week | Off | In About. While on, PaceBar runs the same check at launch, shortly after wake and every 6 hours, but only once a week has passed since the last answer. Automatic checks that fail retry quietly. A found update stays shown, across relaunches, until you install it. |

### Notifications

Notifications are local, through `UserNotifications`, and are evaluated after each refresh. The first time you turn one on, macOS asks for permission. Clicking a notification opens the popover.
- **If permission is missing,** the Notifications tab shows a button. It reads **Allow Notifications…** when macOS hasn't asked yet, and **Open Notification Settings** when notifications were turned off. macOS never asks again after a no, so System Settings is the only way back. The tab picks up the change when you return to PaceBar.
- **No repeats:** the state behind them is kept in memory only. After a launch, PaceBar first records where each limit stands without notifying, so restarting never repeats an alert.
- **New cycles:** a new cycle starts only when a limit's reset time actually moves. Usage easing off as time passes never counts as a reset.
- **No flapping:** Hot notifies once, then re-arms only after the limit is back on track or under pace. That gap is a whole margin wide, so a limit sitting at a zone boundary can't flap.
- **Which limits:** only limits shown in the popover notify. Reminders cover the 5-hour session and the all-models weekly limit.
- **On quit:** pending reminders are removed when PaceBar quits.

## Widgets

Add them like any other widget: click the date in the menu bar and choose **Edit Widgets**, or right-click the desktop and choose **Edit Widgets**, then search for PaceBar. There are three:
- **Claude Limit** (small): one limit as a ring, with its zone and reset time.
  - To choose the limit, right-click the widget and choose **Edit Widget**. The choices are the 5-hour session, Weekly, and any per-model weekly limit the API has reported. The default is the 5-hour session.
  - If the chosen limit is hidden in the popover, the widget falls back to the 5-hour session, then to the first limit shown.
- **Claude Usage, medium:** the first two limits as pacing bars, beside a usage graph.
  - Right-click › **Edit Widget** › Graph chooses the graph. The choices are the 5-hour session (the default), Weekly, a per-model weekly limit, or **5-Hour Session and Weekly**, which stacks two shorter graphs.
- **Claude Usage, large:** up to three limits. Each shows its zone, percentage, reset time, how far it is from a steady pace, its pacing bar, and a usage graph that grows to fill the space. With two or fewer limits, it also shows weekday names on weekly graphs and, when you're running hot, when you'd be back on pace. A footer shows when the data was fetched, next to the refresh button.

Widgets follow your settings: theme (including Custom colors), color mode, thresholds, workweek pacing, which limits the popover shows, and the usage graph and day options. Clicking a widget opens the popover.

**Refresh button** (↻, top right; bottom right on the large widget):
- It asks PaceBar to bring the widgets up to date. PaceBar redraws them with what it already has, then fetches, with the same limit as opening the popover: not if the data is under 30 seconds old.
- For about 20 seconds after a click, every update reaches the widgets immediately.
- The widget can't fetch on its own, so this does nothing while PaceBar isn't running.

**How they get data.** A widget runs in its own sandboxed process with no network access, so it can't read the Keychain. After each refresh PaceBar writes `snapshot.json` to a folder it shares with the widget, `~/Library/Group Containers/<TEAM_ID>.io.github.mdjhnson.pacebar/`. The file holds:
- each shown limit's percentage and reset time
- up to 120 of this cycle's readings per limit, for the graph
- the display settings above, with the theme already resolved to colors
- when the data was fetched, the refresh interval, and whether the last refresh failed

It never holds the token, any response body, or anything else from the Keychain. PaceBar replaces the file on each refresh.

**Updates.** Widgets recompute pacing every 15 minutes from the last snapshot, so zones keep moving even with no new data. PaceBar also asks macOS to redraw them as soon as a setting changes, an error starts or ends, or a limit resets. Other changes reach them at most every 5 minutes, and new graph readings at least every 30 minutes, which keeps PaceBar inside macOS's daily widget update budget. In between, a widget can be a point behind the menu bar; the refresh button catches it up.

**When PaceBar isn't running,** widgets keep showing the last snapshot. After a failed refresh, or once the data is more than 45 minutes old (or twice the refresh interval, if that's longer), they dim it and show "Updated N min ago". The allowance is long because a running PaceBar with unchanged numbers only redraws widgets every 30 minutes, and a widget learns how fresh the data is only when it's redrawn. Before PaceBar has ever run, they show "Open PaceBar to start."

## Threat model and security design

PaceBar holds a **full-scope Claude Code OAuth token** in memory while a request is in flight. Anyone who obtains that token can act as your Claude account. The design aims to keep the token's exposure as small as practical.

### What the app does with the token

- It reads the token from the macOS Keychain on every refresh, uses it for one HTTPS request, then drops it. The token is never cached between refreshes.
- It never writes, modifies or refreshes any credential. If the token has expired, the app asks you to open Claude Code so it can refresh its own login.
- The token is never written to disk, `UserDefaults`, logs, the pasteboard or any cache. It never appears in a command-line argument, environment variable or URL.
  - Its type redacts itself in every `description`, `debugDescription` and `Mirror`, so it can't be printed by accident.
- **Limitation:** Swift `String` storage can't be reliably zeroed, so freed memory may still hold the token until it is reused. A process that can read PaceBar's memory can already do much worse.

### Network

- **Two hosts, each with one fixed URL:**
  - `https://api.anthropic.com/api/oauth/usage`, the usage request, from `UsageClient.swift`. It's the only request that carries the token.
  - `https://api.github.com/repos/mdjhnson/claude-usage-monitor/releases/latest`, the update check, from `UpdateClient.swift`. It runs only when you click **Check for Updates**, or weekly if you turn that on (off by default). It sends no token, cookie or account data, just `User-Agent: PaceBar` (GitHub requires one), so GitHub sees your IP address and that PaceBar asked. Only the `tag_name` field is read. The Download link opens a fixed release-page address, never a URL from the response.
- There is no analytics, telemetry, crash reporting or auto-update.
- Each request URL is checked right before sending: https only, the exact host for that client, default port, no user info. The response URL is checked again.
- **Every redirect is refused,** including same-host redirects.
- Both sessions are ephemeral, with no cookie store, URL cache or credential storage. TLS 1.2 is the minimum.
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
- **Hardened runtime is on.** The app's entitlements are `com.apple.security.network.client` and one App Group, `<TEAM_ID>.io.github.mdjhnson.pacebar`. There are no library-validation or JIT exceptions. Release builds carry no `get-task-allow`, so a debugger can't attach.
- **The widget extension is sandboxed** (`com.apple.security.app-sandbox`), with no network entitlement. Its only other entitlement is the same App Group. Its code reads `snapshot.json` and draws it. It has no networking, subprocess, Keychain, notification or URL-opening code, and can't reach Claude Code's login.
- **The refresh button** posts a Darwin notification named `<TEAM_ID>.io.github.mdjhnson.pacebar.refresh`. It carries no data, and PaceBar treats it exactly like opening the popover. Any local process can post one, but the most it can do is ask for a refresh, which is limited to one every 30 seconds and still subject to the rate-limit backoff.
- **One file on disk:** the widget snapshot (see **Widgets**), written only by `WidgetSnapshot.swift`. It holds usage percentages, reset times, recent readings and display settings, never the token.
- There are no listening sockets, no URL scheme handlers, no AppleScript, and no files written into `~/.claude`.
- The only app PaceBar launches is `/System/Applications/Utilities/Terminal.app`, at a fixed path, from the setup guide.
- It opens exactly three fixed URLs: this repository's GitHub page and its latest release page, from the links in Settings › About, in your default browser; and PaceBar's page in System Settings › Notifications (`x-apple.systempreferences:…?id=io.github.mdjhnson.pacebar`), from the Notifications tab, which opens locally.
- **No auto-update.** The optional update check only tells you a newer version exists. You update by pulling and rebuilding, or by installing a newer DMG.

### Failure behavior

On any error, the last good data stays on screen, dimmed, with "Last updated N min ago" and a short message.
- Malformed responses never crash the app. Unknown keys are ignored, and a broken bucket is dropped individually. That includes a non-finite or absurd value (beyond ±1,000,000%).
- **HTTP 429:**
  - `Retry-After` is honored, whether sent as seconds or as an HTTP date, up to a one-hour sanity bound.
  - Without the header, the wait doubles from the refresh interval each time, capped at 15 minutes.
  - Waking the Mac doesn't skip a running backoff.
  - The limit applies per login, so while waiting PaceBar checks the Keychain once a minute (locally, no request). If Claude Code has renewed its login since the 429, PaceBar retries straight away.
  - The message says this is on Anthropic's side and there's nothing to fix. It doesn't send people to Terminal.
- **Keychain timeouts:** background refreshes allow the `security` call 3 seconds (on recent macOS it can hang when launched from a menu bar app). The first read after launch, and any read you start with Retry, allow 60 seconds, so there's time to answer the macOS prompt.
- **Keychain denial:** if you deny access, background refreshes stop asking until you click Retry.

### Auditing

`./scripts/audit.sh` lists every line in `Sources/` containing `http://`, `https://`, `Process`, `URLSession`, `UserDefaults`, `print(` or `NSLog(`. It then fails if any rule is broken:
- the only literal hosts are `api.anthropic.com` and `api.github.com`, and a URL whose host is built at runtime also fails. The exceptions are `https://claude.ai/install.sh` in `SetupGuideView.swift`, which is copied to the clipboard and never fetched, and the About tab's two links in `AboutView.swift`, `https://github.com/mdjhnson/claude-usage-monitor` and its `/releases/latest` page.
- `api.github.com` appears only in `UpdateClient.swift`, as the one fixed `latestURL`, and that file holds no other URL. It has no `Authorization`, `OAuthCredential`, `accessToken`, `KeychainTokenReader`, `SecItem` or `UserDefaults`, so the token can't reach GitHub.
- URLs are opened in exactly three places: `Link(Self.repository, destination: Self.repositoryURL)` and `Link("Download", destination: Self.releasesURL)` in `AboutView.swift`, with both URLs fixed, and one `NSWorkspace.shared.open(Self.notificationSettingsURL)` in `Notifier.swift`, with `notificationSettingsURL` fixed to PaceBar's System Settings page. Any other `Link(`, `openURL` or `NSWorkspace.open(` fails.
- the only app launch is one `openApplication` call in `SetupGuideView.swift`, opening the fixed Terminal.app path
- networking APIs (`URLSession`, `URLRequest`, `URLComponents`, host assignment) appear only in `UsageClient.swift` and `UpdateClient.swift`
- `Process` appears only once, in `KeychainTokenReader.swift`
- no forbidden constructs:
  - Keychain data or write APIs
  - shells, exec/spawn/popen, AppleScript
  - sockets and listeners, web views, URL opening (other than the three links above)
- `Sources/` contains only Swift files
- `Package.swift` declares no dependencies, binary targets, plugins or unsafe/linker flags; `project.yml` declares no packages, prebuilt frameworks or extra flags, and `PaceBar.xcodeproj` references no remote package
- the app's entitlements are exactly `com.apple.security.network.client` and `com.apple.security.application-groups`; the widget's are exactly `com.apple.security.app-sandbox` (true) and `com.apple.security.application-groups`; the only App Group in either is `$(TeamIdentifierPrefix)io.github.mdjhnson.pacebar`; Release builds don't inject `get-task-allow`; and Info.plist declares no URL schemes
- files are written, and the App Group container opened, only in `WidgetSnapshot.swift`
- `Sources/PaceBarWidget` contains no networking, `Process`, Keychain, notification, `NSWorkspace` or link code
- the only Darwin notification is the refresh request: posted only in `RefreshIntent.swift`, observed only in `WidgetPublisher.swift`, with its name built only in `WidgetSnapshot.swift`. No distributed notifications.

## Copy diagnostic

Settings › Copy diagnostic copies a plain-text report.

**It includes:**
- app and macOS versions
- the number of Keychain items under the service
- whether a token was found, and its expiry relative to now
- the last HTTP status and error kind
- the refresh interval and backoff state
- the response's **shape**: every key path with its JSON type. Values appear only at three exact paths, `limits[].kind`, `limits[].group` and `limits[].scope.model.display_name`, because those name limit types and models. Dates show their format only. Keys that aren't plain lowercase field names print as `<key>`.

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

[DESIGN_NOTES.md](DESIGN_NOTES.md) has the exact visual spec. Two differences from TokenEater are deliberate:
- **The website** shows the "On track" pill in amber, on a fixed green-to-amber bar.
- **The app source** colors "On track" blue (`#0A84FF`) and "Chill" green in its default theme, uses amber (`#FF9500`) for the "Watch out" zone, and colors the whole bar by the current zone.
- **PaceBar** follows the app source but swaps the first two: "Chill" is blue (`#0A84FF`) and "On track" is green (`#32D74B`), in every theme except Monochrome.

## Uninstall

1. If you turned on Launch at login, turn it off in Settings first, or remove PaceBar later in System Settings › General › Login Items.
2. Quit PaceBar (popover › Quit), then delete `PaceBar.app`.
3. Remove its preferences: `defaults delete io.github.mdjhnson.pacebar`.
4. Remove the widget snapshot: `rm -rf ~/Library/Group\ Containers/*.io.github.mdjhnson.pacebar`. Remove any PaceBar widgets first, or they'll show "Open PaceBar to start."
5. Optional: in Keychain Access, open "Claude Code-credentials" › Access Control and remove `security` if you don't want other tools to keep prompt-free access.

PaceBar writes nothing else to disk. If you turned on notifications, macOS keeps a PaceBar entry in System Settings › Notifications; deleting the app is enough, or remove it there.

## Not implemented

These are out of scope for v1. The code has clean seams for them, but none are built:
- Codex or other provider tracking
- usage history or session-log parsing
- agent watchers
- extra-credits (`extra_usage`) display

Also not done:
- **User-Agent version detection.** The app sends `claude-code/0.0.0`. If the endpoint starts rejecting that, add version detection from file metadata, with no shell.
- **Auto-update.** Check for Updates only links to the release page. Installing is still dragging the new DMG's app into Applications.
- **Localization.** English only.

## License

MIT. See [LICENSE](LICENSE).

## Credits

The pacing model, quips, theme presets and visual design follow TokenEater by AThevon (MIT). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
