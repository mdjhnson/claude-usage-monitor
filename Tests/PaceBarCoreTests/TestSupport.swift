import Foundation
@testable import PaceBarCore

/// Gregorian calendar fixed to New York so DST transitions are deterministic.
let newYork: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

/// Builds a local New York date.
func ny(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

let hour: TimeInterval = 3600
let day: TimeInterval = 24 * hour

func schedule(days: Set<Int> = WorkSchedule.workweek, hours: (Int, Int)? = nil) -> WorkSchedule {
    WorkSchedule(
        enabled: true,
        activeDays: days,
        hoursEnabled: hours != nil,
        startHour: hours?.0 ?? 9,
        endHour: hours?.1 ?? 18
    )
}
