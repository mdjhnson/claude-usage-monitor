import Foundation
import PaceBarCore

/// User-facing strings for times and percentages.
enum Format {
    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return "\(Int(clamped(value).rounded()))%"
    }

    /// "+7%", "−4%" (true minus sign), "0%".
    static func signedPercent(_ delta: Double) -> String {
        guard delta.isFinite else { return "–" }
        let n = Int(clamped(delta).rounded())
        if n > 0 { return "+\(n)%" }
        if n < 0 { return "\u{2212}\(-n)%" }
        return "0%"
    }

    /// Keeps Double-to-Int conversion in range so display code can never trap.
    private static func clamped(_ value: Double) -> Double {
        min(max(value, -1_000_000), 1_000_000)
    }

    /// Session: "resets in 2h 14m". Weekly: "resets tomorrow 4:00 AM", "resets Tue 3:00 PM",
    /// or "resets Oct 16, 3:59 AM" a week out, so a reset on today's weekday isn't misread.
    static func resetCountdown(kind: WindowKind, resetsAt: Date, now: Date) -> String {
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return "resets now" }
        if kind == .session { return "resets in " + duration(remaining) }
        return "resets " + dayTime(resetsAt, now: now)
    }

    /// "Back on pace around 3:10 PM" today, otherwise with the day.
    static func cooling(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let when = calendar.isDate(date, inSameDayAs: now) ? time(date) : dayTime(date, now: now, calendar: calendar)
        return "Back on pace around " + when
    }

    /// "today 3:59 AM", "tomorrow 3:59 AM", "Wed 3:59 AM" within the week, else "Oct 16, 3:59 AM".
    static func dayTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "today " + time(date)
        case 1: return "tomorrow " + time(date)
        case 2...6: return weekdayTime(date)
        default: return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }

    /// "just now", "1 min ago", "12 min ago", "3 h ago".
    static func age(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h ago" }
        return "\(hours / 24) days ago"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded(.up)))
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func weekdayTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "9 AM", "6 PM", and "Midnight" for an end hour of 24, in the user's clock style.
    static func hour(_ hour: Int) -> String {
        if hour >= 24 { return "Midnight" }
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour)) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    /// "3 min", "3 min 30 s" for the refresh interval.
    static func interval(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60, s = total % 60
        return s == 0 ? "\(m) min" : "\(m) min \(s) s"
    }
}
