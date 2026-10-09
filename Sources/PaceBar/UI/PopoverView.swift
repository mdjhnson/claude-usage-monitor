import AppKit
import SwiftUI
import PaceBarCore

/// The dark dashboard shown from the menu bar item.
struct PopoverView: View {
    let store: UsageStore
    let settings: SettingsStore
    let openSettings: () -> Void

    var body: some View {
        let theme = Theme.preset(settings.themePreset)
        TimelineView(.periodic(from: .now, by: 20)) { context in
            content(theme: theme, now: context.date)
        }
        .frame(width: 300)
        .background(theme.popoverBackground)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(theme: Theme, now: Date) -> some View {
        let text = theme.textColor
        let stale = store.isStale(now: now)

        VStack(spacing: 0) {
            HStack {
                Text("PaceBar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(text.opacity(0.9))
                Spacer()
                RefreshButton(
                    isRefreshing: store.isRefreshing,
                    isDisabled: store.isBackingOff(now: now),
                    color: text,
                    action: store.retry
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 10) {
                if let error = store.lastError {
                    ErrorBanner(
                        message: error.message(retryAt: store.retryNotBefore),
                        isAuthProblem: error.isAuthProblem,
                        canRetry: !store.isBackingOff(now: now) && !store.isRefreshing,
                        textColor: text,
                        onRetry: store.retry
                    )
                }

                if stale, let snapshot = store.snapshot {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Last updated \(Format.age(since: snapshot.fetchedAt, now: now))")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(text.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let snapshot = store.snapshot {
                    let reported = snapshot.usage.windows
                    let windows = reported.filter { !settings.popoverHiddenWindowIDs.contains($0.id) }
                    if windows.isEmpty {
                        Text(reported.isEmpty
                             ? "No usage windows were reported for this account."
                             : "All windows are hidden. Choose some under Settings › Windows.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(text.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(windows) { window in
                        let pacing = settings.pacing(for: window, now: now)
                        WindowCard(
                            window: window,
                            pacing: pacing,
                            tint: theme.tint(
                                utilization: window.bucket.utilization, pacing: pacing, mode: settings.colorMode,
                                warningAt: settings.warningThreshold, criticalAt: settings.criticalThreshold
                            ),
                            theme: theme,
                            stale: stale,
                            now: now
                        )
                    }
                } else if store.lastError == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading Claude Code login…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(text.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .padding(.horizontal, 16)

            footer(text: text, now: now)
        }
    }

    private func footer(text: Color, now: Date) -> some View {
        VStack(spacing: 8) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack(spacing: 12) {
                if let snapshot = store.snapshot {
                    Text("Updated \(Format.age(since: snapshot.fetchedAt, now: now))")
                        .font(.system(size: 10))
                        .foregroundStyle(text.opacity(0.3))
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(text.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(text.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

private struct RefreshButton: View {
    let isRefreshing: Bool
    let isDisabled: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(0.04))
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.opacity(isDisabled ? 0.25 : 0.6))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: isRefreshing)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isRefreshing)
        .help(isDisabled ? "Waiting for the rate limit to clear" : "Refresh now")
        .accessibilityLabel("Refresh")
    }
}

private struct ErrorBanner: View {
    let message: String
    let isAuthProblem: Bool
    let canRetry: Bool
    let textColor: Color
    let onRetry: () -> Void

    private static let red = Color(red: 0.97, green: 0.44, blue: 0.44)

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(isAuthProblem ? Self.red : .orange)
            Text(LocalizedStringKey(message))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(textColor.opacity(0.7))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textColor.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(isAuthProblem ? Color.white.opacity(0.08) : Color.orange.opacity(0.3)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }
}
