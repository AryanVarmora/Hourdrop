import Foundation

/// Fixed dates for tests, in UTC, so they give the same answers in any time zone
/// and on daylight-saving days.
enum TestTime {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// e.g. date(2026, 10, 18, 14, 30) is Oct 18, 2026 at 2:30 PM.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

/// A new, empty folder for one test, inside the system's temporary folder.
func makeTempFolder() throws -> URL {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("HourdropTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
