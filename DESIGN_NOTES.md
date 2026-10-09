# PaceBar design notes

This is the visual spec PaceBar implements, taken from the TokenEater source at `AThevon/TokenEater@9054498` (MIT). Correct anything here before UI work starts.

Sources: `Shared/Models/ThemeModels.swift`, `Shared/Components/PacingBar.swift`, `Shared/Components/OffDayHatch.swift`, `Shared/Components/GlowText.swift`, `Shared/Extensions/Extensions.swift` (`lighter`), `TokenEaterApp/Popover/ComposablePopoverView.swift`, `PopoverCells.swift`, `PopoverShared.swift`, `Shared/Helpers/MenuBarRenderer.swift`, `TokenEaterApp/App/StatusBarController.swift`.

## Discrepancies between website and app

| Item | Website feature card (per brief) | App source | PaceBar uses |
|---|---|---|---|
| "On track" color | Amber border and text | Default theme `pacingOnTrack = #0A84FF` (blue). Amber `#FF9500` is the **warning** zone. | App source (blue) |
| Bar gradient | Green to amber | Zone color to `zoneColor.lighter()` | Zone color to lighter zone color (see note 1) |
| Zone pill, "+7%" delta, quip | Shown | Not in the popover. Quips exist in `PacingResult.message`, but no popover cell renders them. | Built per the brief, using app tokens |
| `0% 50% 100%` axis labels | Dim monospace labels under the bar | Not in `PacingBar` or `HeroPacingGraph` | Built per the brief |

Note 1: the brief says "gradient fill from the theme's low color to the theme's warning color". The app instead colors the whole fill by the current zone, so a bar in the "hot" zone is red. I'm following the app because it also carries the zone at a glance. If you'd prefer the website's fixed green-to-amber look, say so. It's a one-line change.

## Theme tokens (exact reference hex)

| Preset | gaugeNormal | gaugeWarning | gaugeCritical | pacingChill | pacingOnTrack | pacingWarning | pacingHot | background | text |
|---|---|---|---|---|---|---|---|---|---|
| Default | #22C55E | #F97316 | #EF4444 | #32D74B | #0A84FF | #FF9500 | #FF453A | #000000 | #FFFFFF |
| Monochrome | #8E8E93 | #C7C7CC | #FFFFFF | #8E8E93 | #AEAEB2 | #D6D6D6 | #FFFFFF | #000000 | #FFFFFF |
| Neon | #00FF87 | #FFD000 | #FF006E | #00FF87 | #00D4FF | #FFD000 | #FF006E | #0A0A0A | #FFFFFF |
| Pastel | #86EFAC | #FDE68A | #FCA5A5 | #86EFAC | #93C5FD | #FDE68A | #FCA5A5 | #1A1A2E | #E2E8F0 |

- **Usage thresholds:** warning at 60% or more, critical at 85% or more. Both are adjustable in Settings.
- **`lighter()`:** in HSB, saturation goes down by 0.045 and brightness up by 0.15, capped at 1.
- **Popover background:**
  - TokenEater uses a fixed `#141417` (rgb 0.08, 0.08, 0.09) and ignores the theme's `widgetBackground`.
  - PaceBar uses `#141417` for Default. For the other presets it uses the preset's `background` blended 50% toward `#141417`, so neon and pastel keep their tint.
  - Text colors use the preset's `text` token.

## Popover

- Width 300pt, height fits the content. Always `darkAqua`, as in TokenEater.
- Outer padding is 16 horizontal, 12 top and 10 bottom. Cards are 10pt apart.
- **Header row:**
  - "PaceBar" at 13 semibold, text at 0.9 opacity.
  - Refresh button on the trailing side: a 22pt circle with `white 0.04` fill and a `white 0.08` stroke at 0.5pt, holding an `arrow.clockwise` icon at 10 semibold, 0.6 opacity.
  - The icon spins while a refresh is in flight.

### Window card (one per window: 5-hour, weekly, each per-model weekly)

**Container** (TokenEater `popoverCard`):
- `RoundedRectangle(cornerRadius: 12)` filled with `white.opacity(0.03)`
- 0.5pt inset border (`strokeBorder`) in `white.opacity(0.05)`
- Inner padding 12; vertical stack with 8pt spacing

**Contents, top to bottom:**

1. **Header row**
   - **Window label**, leading: "5-HOUR SESSION", "WEEKLY" or "WEEKLY · SONNET". 9 semibold, uppercase, tracking 0.6, `white 0.45`.
   - **Workweek badge:** `briefcase.fill`, or `moon.zzz.fill` during off time. 9 semibold at 0.45. Shown only on weekly cards when the schedule is on.
   - **Reset countdown**, trailing, 10 medium at `white 0.35`:
     - Session: "resets in 2h 14m", or "resets in 25m".
     - Weekly: "resets Tue 3:00 PM", using the locale's short weekday and time.
2. **Usage row**
   - **Percentage:** "42%", 24 black `.rounded`, in the zone color (or threshold color when color mode is "Usage threshold").
   - **Glow:** a shadow in the same color at 0.5 opacity, radius 4 (`GlowText`).
3. **Pacing bar** (TokenEater `PacingBar`, non-compact):
   - Frame height 20, with the bar vertically centered.
   - **Track:** 8pt tall, corner radius 4 (fully rounded), `white.opacity(0.06)`.
   - **Off-time hatch** (workweek on):
     - Each off range gets a `white 0.04` fill.
     - 0.75pt diagonal lines at `white 0.11`, 4pt apart, clipped to the track.
   - **Fill:** width = usage%. `LinearGradient(zoneColor → zoneColor.lighter(), leading → trailing)`, radius 4.
   - **Knob (actual usage):**
     - 10pt white circle centered on the end of the fill.
     - White shadow at 0.5 opacity; the radius pulses 2↔6 with `easeInOut(1.5s).repeatForever`.
     - During off time: white at 0.45 with a 0.2 shadow.
   - **Expected-pace marker:**
     - Upward triangle 10pt wide and tall, `white 0.5` (0.25 during off time).
     - Vertically centered on the track, like the knob; the knob draws on top.
     - x = expected%, or calendar "now" when the workweek schedule is active, so it lines up with the hatch (TokenEater issue #194).
   - **Motion:** the fill springs in from 0 on appear (`response 0.8, damping 0.7`) and on value change (`0.6, 0.8`).
4. **Axis labels:** "0%", "50%" and "100%" at leading, center and trailing. 9 regular `.monospaced`, `white 0.3`.
5. **Zone row**
   - **Pill:**
     - capsule, 1pt inset border in the zone color, zone color at 0.12 fill
     - text "On track", "Chill", "Watch out" or "Hot", 10 semibold in the zone color
     - padding 8 horizontal, 3 vertical
   - **Delta:** "+7%" or "−4%", 11 semibold `.rounded`, `white 0.5`, 6pt after the pill.
6. **Quip:** 11 medium, `white 0.6`. The text picks one of 3 variants by `abs(Int(delta)) % 3`, using TokenEater's copy:

   | Zone | Session (5h) | Weekly |
   |---|---|---|
   | Chill | Cool 5h · Time to spare · Easy session | Easy week · Plenty of week · Calm cycle |
   | On track | Locked in · Session rhythm · Right on the hour | Weekly cadence · Steady week · Marathon rhythm |
   | Warning | Session warming · 5h edging up · Tempo creeping | Week picking up · Pace creeping · Cadence edging |
   | Hot | 5h on fire · Session blazing · Burning the hour | Week's burning · Cycle blazing · Torching the week |

7. **Cooling line** (only in the Watch out and Hot zones, that is, delta > margin): "Back on pace around Tue 3:10 PM", or just the time if it falls today. 10 medium, `white 0.4`.

**Card variants:**
- **No reset time** (`resets_at` is null): the percentage, then "Reset time not reported, so pacing is unavailable." in 10 medium at `white 0.4`. No bar, pill or quip.
- **Stale data:**
  - The percentage, bar and pill drop to 0.45 opacity on every card.
  - One line above the cards reads `clock.arrow.circlepath` plus "Last updated 12 min ago", 10 regular at `white 0.45`.

### Error banner (above the cards)

- **Container:** padding 10, `white 0.04` fill, radius 8.
- **Icon:**
  - Auth and Keychain problems: `exclamationmark.triangle.fill` in red `rgb(0.97, 0.44, 0.44)`.
  - Network and rate limits: orange.
- **Message:** 11 medium, text at 0.7, up to 3 lines.
- **Retry button:** a capsule with 11 semibold text, padding 10×4.
  - Fill is `white 0.08` for auth errors and `orange 0.3` for network or rate-limit errors.
  - While a rate-limit backoff is active, the button is disabled and the message shows the retry time.
- **First-run states, before any data:**
  - Before any data: a spinner with "Reading Claude Code login…".
  - If reading the login fails, the banner appears on its own.

### Footer

- "Updated 2 min ago" at 10, `white 0.3`.
- Then a gear icon that opens Settings, and "Quit" at 10 medium, `white 0.4`.
- 8pt above the footer is a hairline divider, `white 0.06`.

## Menu bar item

- Drawn as a non-template `NSImage`, 22pt tall. Segments sit 6pt apart, with 1pt padding at each edge.
- The image is redrawn when the button's `effectiveAppearance` changes, so dynamic label colors track light and dark menu bars.
- **Classic style (default)**, per window:
  - Label "5h", "7d" or "Son": `systemFont 9 .medium`, `secondaryLabelColor`.
  - Value "42%": `monospacedDigitSystemFont 12 .bold`, in the zone color or threshold color.
- **Pill style:**
  - Capsule 17pt tall, horizontal padding 7, radius 8.5.
  - Fill: tint at 0.18 alpha. Stroke: tint at 0.55 alpha, 0.8pt wide.
  - Text "5h 42%": `systemFont 11 .bold` in the tint.
- **Monochrome option:** draws with `labelColor` instead of theme colors, for people who want a quiet menu bar.
- **Fallback states:**
  - No data yet, or no windows selected: a `gauge.with.needle` template SF Symbol.
  - Error and no data: an `exclamationmark.triangle` template SF Symbol.
  - Stale data: values drawn at 0.5 alpha.
- **Color mode:**
  - "Pacing zone" (default): the window's zone color.
  - "Usage threshold": `gaugeNormal`, `gaugeWarning` or `gaugeCritical`, using the thresholds.
  - A window with no `resets_at` always uses threshold colors.

## Settings window

A plain titled `NSWindow`, 460pt wide, using SwiftUI `Form` with `.formStyle(.grouped)` and the system appearance. Sections:

1. **Pacing:**
   - Margin slider, 5–20, step 1, showing "±10%".
   - Workweek toggle; when on, weekday chips (S M T W T F S).
   - "Active hours" toggle with start and end hour pickers. Start is 0–23, end is 1–24, where 24 means midnight.
2. **Menu bar:**
   - A checkbox for each window seen in the last response. 5h and weekly are on by default.
   - Style: Classic / Pill.
   - Color mode: Pacing zone / Usage threshold.
   - Monochrome toggle.
3. **Appearance:**
   - Theme preset picker, showing four colored dots per preset.
   - Warning and critical threshold steppers.
4. **General:**
   - Refresh interval stepper, 60–600 s, step 30.
   - Launch at login toggle. Shows "Approve in System Settings › Login Items" when the status is `.requiresApproval`.
5. **Diagnostics:**
   - "Copy diagnostic" button, with a short caption saying what is included.

## Fonts summary

All text uses SF (`.system`). Percentages and deltas use `.rounded`. Axis labels use `.monospaced`. Menu bar values use monospaced digits so widths don't jitter.
