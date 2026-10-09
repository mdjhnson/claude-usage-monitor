# Brief: PaceBar, a minimal Claude usage and pacing menu bar app for macOS

Working name: **PaceBar** (rename freely). Hand this whole file to Claude Code as the project brief. Put it in the repo root as `BRIEF.md`.

## 1. Goal

Build a small, native macOS menu bar app that shows my Claude usage limits and a "smart pacing" indicator. It must look and feel like TokenEater's menu bar and popover, but with a much smaller code base that I fully own and can audit in one sitting.

Priorities, in order:
1. Security and a tiny attack surface.
2. Correct pacing math (spec in section 5).
3. Look and feel matching TokenEater (section 6).
4. Polish and optional features.

Production quality is expected: no placeholders, no TODO stubs, no partial examples. Everything described under "v1 scope" must work end to end.

## 2. Reference material (read, do not blindly copy)

I have a clone of TokenEater (MIT licensed, https://github.com/AThevon/TokenEater). Clone it read-only next to this project, for example `../TokenEater-reference`, and study these files for behavior and visuals:

- `Shared/Helpers/PacingCalculator.swift` and `Shared/Models/PacingModels.swift` (pacing math and zones)
- `Shared/Components/PacingBar.swift` (the pacing bar visuals)
- `Shared/Models/ThemeModels.swift` (theme tokens and presets)
- `TokenEaterApp/Popover/` and the menu bar composition code (layout of rings, chips, bars)
- `Shared/Services/SecurityCLIReader.swift` and `Shared/Services/APIClient.swift` (credential read and request shape)
- `Shared/Models/UsageModels.swift` (response decoding, including the `limits[]` array migration)

I will also attach a screenshot of TokenEater's "Smart Pacing" feature card from its website. It shows: a rounded dark card, a fully rounded horizontal bar with a green to amber gradient fill, a white circular knob on the bar, a pill reading "On track" with an amber border and amber text, a gray "+7%" delta next to it, and dim monospace axis labels "0%", "50%", "100%" under the bar.

Rules for using the reference:
- Re-implement in your own code. Do not paste whole files.
- If any substantial portion of code is copied or closely adapted, keep the MIT copyright notice for TokenEater in a `THIRD_PARTY_NOTICES.md` file.
- Do not guess colors or spacing. Read `PacingBar.swift`, `ThemeModels.swift`, and the popover views, and match them. Where the website screenshot and the app source disagree (for example the website shows amber for "On track" while the default theme token may differ), prefer the app source for the in-app UI and note the discrepancy in the README.

## 3. Hard security requirements (non-negotiable)

This app holds a full-scope Claude Code OAuth token in memory. Treat that as the crown jewel.

1. **One network host only:** `api.anthropic.com`. No other host, no analytics, no telemetry, no heartbeat, no update checks, no crash reporting. No third-party Swift packages at all (zero dependencies).
2. **Read-only credentials.** Read Claude Code's token from the macOS Keychain. Never write to, modify, or refresh any credential. If the token is expired, show a clear message telling me to open Claude Code so it refreshes its own login.
3. **The token lives in memory only.** Never write it to disk, UserDefaults, logs, crash output, pasteboard, or any cache. Never put it in a command line argument, environment variable, or URL. Do not log request headers. Use `os.Logger` and mark any dynamic string `privacy: .private`.
4. **Redirect lock.** Use a `URLSession` delegate that refuses any redirect, and assert the request host is exactly `api.anthropic.com` before sending. Use an ephemeral session configuration (no cookie or cache storage).
5. **No auto-update.** Updates happen when I rebuild from source.
6. **Hardened runtime on.** Entitlements: `com.apple.security.network.client` only. Do NOT add `disable-library-validation`, `allow-unsigned-executable-memory`, or any other exception. The app is not sandboxed because it must read another app's Keychain item through `/usr/bin/security`; document that in the README.
7. **Subprocess policy.** The only subprocess allowed is `/usr/bin/security` (absolute path), with fixed arguments. No shell, no `Process` with user-influenced strings, no AppleScript, no `osascript`.
8. **No local server.** No listening sockets, no URL scheme handlers, no hooks into Claude Code settings, no files written into `~/.claude`.
9. **Fail closed and quiet.** On any error, keep showing the last good data marked as stale, and show a short human-readable error in the popover. Never crash on malformed responses.
10. **Supply chain:** pin the toolchain version in the README, commit `Package.resolved` if SwiftPM is used (it should have no dependencies anyway), and add a CI-free `scripts/audit.sh` that greps the source for `http://`, `https://`, `Process(`, `URLSession`, `UserDefaults`, `print(`, and `NSLog(` and lists every hit so I can review them in one command.

## 4. Data source and credential handling

### 4.1 Reading the token

Claude Code stores its login in the Keychain as a generic password with service `Claude Code-credentials`. Read it by running:

```
/usr/bin/security find-generic-password -s "Claude Code-credentials" -a <account> -w
```

Details:
- Run on a background thread with a **3 second timeout**; terminate the child if it hangs (on macOS 26 this call can block indefinitely when launched from an LSUIElement app).
- There can be more than one item under that service, and a "shadowing" item may exist that carries no OAuth data. Enumerate accounts with `SecItemCopyMatching` asking for **attributes only** (`kSecReturnAttributes`, never `kSecReturnData`, which avoids an ACL prompt). Then read each account's payload with the `security` command above.
- The payload is JSON. Take `claudeAiOauth.accessToken` (string) and `claudeAiOauth.expiresAt`. `expiresAt` is milliseconds since epoch; if the number is small enough to be seconds, treat it as seconds. Ignore items with no `claudeAiOauth` or an empty token. If several items qualify, use the one with the latest `expiresAt`.
- Exit code 44 means "item not found": show "Sign in to Claude Code first (`claude` then `/login`)". Exit code 45 means access denied: show instructions to click "Always Allow" on the macOS prompt.
- On first run macOS shows a Keychain prompt. Explain in the README that after "Always Allow", the ACL entry belongs to `/usr/bin/security`, so other processes running as me may be able to read the same item without a prompt. This is a property of the approach, not something to hide.
- Re-read the token on every refresh cycle (Claude Code rotates it), hold it only for the duration of the request, then drop it.

### 4.2 Usage request

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/<version>
```

- First try a fixed User-Agent such as `claude-code/0.0.0`. Only if the endpoint rejects it, add best-effort version detection, and keep that detection free of shell execution (for example, read the version from a known install location's metadata).
- Status handling: `200` decode; `401` or `403` token expired (message above); `429` honor the `Retry-After` header, back off exponentially with a cap of 15 minutes, keep showing stale data; other statuses show a short error.
- Polling: default every **180 seconds**, user-configurable between 60 and 600 seconds, plus a refresh when the popover opens (debounced to at most once per 30 seconds). Polling too fast risks 429 on this endpoint. Pause polling when the Mac sleeps and refresh on wake.

### 4.3 Response shape

Decode tolerantly: unknown keys ignored, a broken bucket becomes `nil` and never fails the whole decode. Relevant fields:

- `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus`, and possibly others. Each bucket is `{ "utilization": Double (0 to 100), "resets_at": ISO8601 string }`. `resets_at` may or may not include fractional seconds; support both. A bucket may have a null `resets_at`.
- A `limits` array is replacing the flat `seven_day_*` keys on migrated accounts. Entries of kind `weekly_scoped` carry a model name at `scope.model.display_name` (for example "Fable" or "Sonnet"). Use the flat key if present, otherwise fall back to the matching `limits` entry. See `UsageModels.swift` in the reference.
- `extra_usage` may exist (paid credits). v1 does not need to display it, but must not break on it.

Do not assume the schema. Add a "Copy diagnostic" button in Settings that copies a **redacted** dump (key names and value types, no token, no identifiers) so I can paste it into a bug report. During development, inspect one real response and write the decoding to match it.

## 5. Pacing specification

Windows and durations:
- 5 hour session: 5 hours.
- Weekly (`seven_day`), Sonnet weekly, and any per-model weekly bucket: 7 days.

For each bucket with a `resets_at`:

```
startOfPeriod = resetsAt - duration
elapsedFraction = clamp((now - startOfPeriod) / duration, 0, 1)
expectedUsage = elapsedFraction * 100
delta = utilization - expectedUsage
```

Zones, with a user margin `m` (default 10, slider range 5 to 20):

```
delta < -m          -> chill
-m <= delta <= m    -> onTrack
m < delta <= 2m     -> warning
delta > 2m          -> hot
```

**Workweek schedule** (weekly buckets only; the 5 hour session is never schedule-adjusted):
- Settings: enabled flag, active weekdays using Gregorian numbers (1 = Sunday through 7 = Saturday, default Monday to Friday = 2...6), and an optional active hours window (default 9 to 18, local time, same hours every active day).
- When enabled, measure elapsed over **active seconds only**: `elapsedFraction = activeSeconds(startOfPeriod, now) / activeSeconds(startOfPeriod, resetsAt)`. Off days and off hours do not advance the expected pace. Guard against a zero denominator and an empty day selection (fall back to all seven days).
- Build the active intervals by walking day segments. Resolve hour bounds with `Calendar.date(bySettingHour:...)` so DST days with 23 or 25 hours stay correct. Treat `end == 24` as midnight.

**Cooling date** (when delta > 0): the moment the steady pace line catches up to current usage if I stop now.
- Calendar mode (5 hour window, or weekly with schedule off): `min(now + (delta / 100) * duration, resetsAt)`.
- Schedule mode: `needed = (delta / 100) * totalActiveSeconds`, then walk the remaining active intervals from `now` to `resetsAt`, consuming `needed` and landing on real calendar time (which may be after off time). Never later than `resetsAt`.

Make `PacingCalculator` a pure, dependency-free function that takes `now` as a parameter so it is trivially testable. Provide short rotating copy per zone and window type (for example three variants each for "session" and "weekly"), chosen deterministically from `abs(Int(delta)) % variants.count` so the wording does not flicker between refreshes. Keep the tone light, in the spirit of TokenEater's quips.

## 6. UI and look and feel

Match TokenEater (see section 2). Build with SwiftUI, targeting macOS 14 or later, `LSUIElement = true` (no Dock icon).

**Menu bar item**
- Compact live readout of the most relevant windows (default: 5 hour percentage and weekly percentage), color coded by zone with a thin visual such as a small ring or pill. Let me choose in Settings which windows appear and whether color follows pacing zone or plain usage thresholds.
- Implement with `NSStatusItem` plus an `NSPopover` or `MenuBarExtra(.window)`, whichever gives the cleanest custom rendering. Support light and dark menu bar appearance.

**Popover dashboard** (dark card style like the TokenEater feature card):
- One section per window: 5 hour session, weekly, and any per-model weekly buckets that exist.
- Each section: percentage, a reset countdown ("resets in 2h 14m", or a weekday and time for weekly), the pacing bar, the zone pill with the signed delta (for example "On track  +7%"), the rotating zone message, and when over pace a line like "Back on pace around Tue 3:10 PM" from the cooling date.
- The pacing bar: fully rounded track, gradient fill from the theme's low color to the theme's warning color, a white knob, dim monospace "0%  50%  100%" labels. Reproduce what `PacingBar.swift` does for the expected-pace marker versus the actual-usage fill.
- Stale-data state: dim the numbers and show "Last updated 12 min ago".
- Error state: short message plus a Retry button.

**Themes:** implement a theme token struct (gauge normal, warning, critical; pacing chill, onTrack, warning, hot; background; text) with four presets mirroring TokenEater's (default, monochrome, neon, pastel) and warning and critical percentage thresholds for plain-usage coloring. Read the actual hex values from `ThemeModels.swift` rather than inventing them. Respect the system appearance.

**Settings** (a simple window or a popover tab): pacing margin, workweek schedule (days and hours), refresh interval, which windows show in the menu bar, color mode (pacing zone or usage threshold), theme preset, launch at login via `SMAppService.mainApp`, and the "Copy diagnostic" button.

**Out of scope for v1** (do not build; leave clean extension points): Codex tracking, History from session logs, Agent Watchers, desktop widgets (WidgetKit), notifications, extra credits display. If notifications are added later, they must use `UserNotifications` only.

## 7. Architecture and project setup

- Swift 5.9 or later, SwiftUI, macOS 14+. Plain Xcode project or Swift Package plus an app target; no XcodeGen requirement, no external packages.
- Suggested layout:
  - `Core/PacingCalculator.swift`, `Core/PacingModels.swift`, `Core/WorkSchedule.swift` (pure logic)
  - `Core/UsageModels.swift` (tolerant decoding, including the `limits[]` fallback)
  - `Services/KeychainTokenReader.swift`, `Services/UsageClient.swift` (host lock, redirect refusal, status mapping)
  - `Stores/UsageStore.swift` (polling, backoff, stale state, wake handling), `Stores/SettingsStore.swift`
  - `UI/` for the status item, popover, pacing bar, settings, and theme
- `UserDefaults` may hold only non-sensitive preferences (margin, schedule, theme, refresh interval, window choices). Never tokens or response data.
- Ad hoc or development signing is fine for personal use. Hardened runtime enabled. Provide `build.sh` that builds a Release `.app` into `./build`, and document the first launch steps (right click, Open, if Gatekeeper blocks an unnotarized build).

## 8. Tests (required)

Unit tests, all runnable with one command:
- `PacingCalculator`: each zone boundary (exactly at `-m`, `m`, `2m`), clamping before and after the window, a custom margin, and the 5 hour window being unaffected by schedule.
- Workweek: weekend exclusion, hours window, a DST spring-forward week and a fall-back week, an empty day set falling back to seven days, and `end == 24`.
- Cooling date: calendar mode, schedule mode landing after an off period, and never exceeding `resetsAt`.
- Credential parsing: valid payload, missing `claudeAiOauth`, empty token, `expiresAt` in milliseconds and in seconds, choosing the latest of several items.
- Response decoding: old flat shape, migrated `limits[]` shape, a broken bucket, unknown keys, fractional and non-fractional `resets_at`, null `resets_at`.
- `UsageClient` with a stubbed `URLProtocol`: 200, 401, 403, 429 with and without `Retry-After`, a redirect (must be refused), and a wrong host (must never send).

## 9. Acceptance criteria

- Builds from a clean checkout with one command and runs from the menu bar.
- First launch triggers the Keychain prompt, then shows real 5 hour and weekly usage with pacing zones and deltas.
- With the network cut, the popover shows stale data with an age and a short error, and recovers on reconnect.
- `scripts/audit.sh` shows exactly one network host and one subprocess call site.
- All tests pass.
- The README covers: what it does, the threat model (full-scope token in memory, non-sandboxed, ACL note from 4.1, no auto-update), build and first-run steps, the settings, how to uninstall (delete the app, `defaults delete` its bundle id), and an honest list of what is not implemented.

## 10. Working agreement

- Before writing code, inspect the reference files listed in section 2 and my attached screenshot, then summarize the visual spec you will implement (colors, radii, spacing, fonts) in a short `DESIGN_NOTES.md` so I can correct it early.
- Work in small commits. After each milestone (pure logic and tests, then Keychain and client, then UI, then settings and polish), run the tests and the audit script and report the results.
- If the real API response differs from section 4.3, adapt to reality and tell me what you found. Do not ask me to paste tokens or credentials anywhere; if you need a real response, have the app's "Copy diagnostic" output or a redacted local fixture for it.
- If any requirement here conflicts with making the app work, stop and ask rather than quietly relaxing a security rule.
