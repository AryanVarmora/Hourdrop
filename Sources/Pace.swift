import Foundation

/// Your wake hours as real times, e.g. today 9:00 AM to 10:00 PM.
/// Until earlier than From runs past midnight; From and Until on the same hour means all day.
struct WakeWindow: Equatable {
    let start: Date
    let end: Date

    /// The wake window you're in now, or the most recent one if you're outside wake hours.
    static func current(startHour: Int, endHour: Int, now: Date = .now,
                        calendar: Calendar = .current) -> WakeWindow {
        let startHour = min(max(startHour, 0), 23)
        let endHour = min(max(endHour, 0), 23)
        let hours = (endHour - startHour + 24) % 24
        let length = hours == 0 ? 24 : hours
        let todayStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: now)!
        let start = now >= todayStart ? todayStart : calendar.date(byAdding: .day, value: -1, to: todayStart)!
        return WakeWindow(start: start, end: calendar.date(byAdding: .hour, value: length, to: start)!)
    }

    static func fromPrefs(now: Date = .now) -> WakeWindow {
        current(startHour: Prefs.wakeStartHour.value, endHour: Prefs.wakeEndHour.value, now: now)
    }

    func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// How far through the window `date` is, from 0 to 1.
    func fractionElapsed(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }
}

/// Whether you're keeping up with your goal, compared with drinking evenly through your wake hours.
struct Pace {
    enum Status: Equatable { case ahead, onTrack, behind }

    let drankML: Int      // since your wake hours started
    let expectedML: Int   // where you'd be by now, drinking evenly
    let goalML: Int

    init(drankML: Int, goalML: Int, window: WakeWindow, now: Date) {
        self.drankML = drankML
        self.goalML = goalML
        expectedML = Int(Double(goalML) * window.fractionElapsed(at: now))
    }

    /// How far off still counts as on track: 5% of your goal, at least 150 ml.
    var tolerance: Int { max(150, goalML / 20) }

    /// Positive when ahead, negative when behind.
    var difference: Int { drankML - expectedML }

    var status: Status {
        if difference > tolerance { return .ahead }
        if difference < -tolerance { return .behind }
        return .onTrack
    }

    /// e.g. "On track", "Behind by 400 ml", "Ahead by 1.1 L"
    var summary: String {
        switch status {
        case .onTrack: "On track"
        case .ahead: "Ahead by \(Format.amount(difference))"
        case .behind: "Behind by \(Format.amount(difference))"
        }
    }

    /// Time between reminders at this pace: half as often when ahead, a bit more often when behind.
    func reminderInterval(base: TimeInterval) -> TimeInterval {
        switch status {
        case .ahead: base * 2
        case .onTrack: base
        case .behind: max(base * 0.75, 15 * 60)
        }
    }
}

enum ReminderTiming {
    /// True once `interval` has passed since your last reminder or your last drink,
    /// whichever was later. The first reminder comes right as your wake hours start.
    static func isDue(now: Date, window: WakeWindow, interval: TimeInterval,
                      lastReminder: Date?, lastDrink: Date?) -> Bool {
        guard window.contains(now) else { return false }
        let firstOfDay = window.start.addingTimeInterval(-interval)
        let last = [firstOfDay, lastReminder, lastDrink].compactMap { $0 }.max()!
        return now.timeIntervalSince(last) >= interval
    }
}
