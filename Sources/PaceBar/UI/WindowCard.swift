import SwiftUI
import PaceBarCore

/// One usage window: label, reset countdown, percentage, pacing bar, zone pill, quip, cooling line.
struct WindowCard: View {
    let window: UsageWindow
    let pacing: PacingResult?
    /// Percentage color (pacing zone or usage threshold, per settings).
    let tint: ThemeColor
    let theme: Theme
    let stale: Bool
    let now: Date

    private var text: Color { theme.textColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(Format.percent(window.bucket.utilization))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.color)
                .shadow(color: tint.color.opacity(0.5), radius: 4)
                .opacity(stale ? 0.45 : 1)

            if let pacing {
                pacingSection(pacing)
            } else {
                Text("Reset time not reported, so pacing is unavailable.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(text.opacity(0.4))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(window.kind.title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(text.opacity(0.45))
            if let pacing, pacing.usesSchedule {
                Image(systemName: pacing.isOffTime ? "moon.zzz.fill" : "briefcase.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(text.opacity(0.45))
                    .help(pacing.isOffTime ? "Off time: pacing is resting" : "Workweek pacing on")
            }
            Spacer(minLength: 8)
            if let resetsAt = window.bucket.resetsAt {
                Text(Format.resetCountdown(kind: window.kind, resetsAt: resetsAt, now: now))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(text.opacity(0.35))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func pacingSection(_ pacing: PacingResult) -> some View {
        let zoneColor = theme.zone(pacing.zone)

        VStack(spacing: 2) {
            PacingBar(
                actual: pacing.actualUsage,
                markerFraction: pacing.markerFraction,
                zoneColor: zoneColor,
                offTimeRanges: pacing.offTimeRanges,
                isOffTime: pacing.isOffTime
            )
            HStack {
                Text("0%")
                Spacer()
                Text("50%")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(text.opacity(0.3))
            .accessibilityHidden(true)
        }
        .opacity(stale ? 0.45 : 1)

        HStack(spacing: 6) {
            ZonePill(title: pacing.zone.title, color: zoneColor.color)
            Text(Format.signedPercent(pacing.delta))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(text.opacity(0.5))
                .accessibilityLabel("\(Format.signedPercent(pacing.delta)) versus steady pace")
        }
        .opacity(stale ? 0.45 : 1)

        Text(pacing.message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(text.opacity(0.6))

        // Only worth saying once usage is past the on-track band.
        if let cooling = pacing.coolingDate, pacing.zone == .warning || pacing.zone == .hot {
            Text(Format.cooling(cooling, now: now))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(text.opacity(0.4))
        }
    }
}

struct ZonePill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color, lineWidth: 1))
    }
}
