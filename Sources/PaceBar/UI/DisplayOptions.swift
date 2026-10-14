import Foundation

// Display choices shared by the app and the widget extension, which compiles this file too.

enum ColorMode: String, CaseIterable, Identifiable {
    case pacing, threshold
    var id: String { rawValue }
    var title: String { self == .pacing ? "Pacing zone" : "Usage threshold" }
}

/// How weekly graphs mark the days.
enum WeeklyDayMarkers: String, CaseIterable, Identifiable {
    case off, lines, linesAndNames
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .lines: "Lines"
        case .linesAndNames: "Lines and day names"
        }
    }
}
