import Foundation
import Testing
@testable import HourdropCore

@Suite("Wake hours")
struct WakeWindowTests {
    let calendar = TestTime.calendar

    @Test("A normal day: 9 AM to 10 PM")
    func normalDay() {
        let window = WakeWindow.current(startHour: 9, endHour: 22, now: TestTime.date(2026, 10, 18, 12), calendar: calendar)
        #expect(window.start == TestTime.date(2026, 10, 18, 9))
        #expect(window.end == TestTime.date(2026, 10, 18, 22))
        #expect(window.contains(TestTime.date(2026, 10, 18, 12)))
    }

    @Test("Before wake hours start, the most recent window is yesterday's")
    func beforeStart() {
        let now = TestTime.date(2026, 10, 18, 7)
        let window = WakeWindow.current(startHour: 9, endHour: 22, now: now, calendar: calendar)
        #expect(window.start == TestTime.date(2026, 10, 17, 9))
        #expect(!window.contains(now))
    }

    @Test("Wake hours can run past midnight: 10 AM until 2 AM")
    func pastMidnight() {
        let now = TestTime.date(2026, 10, 19, 1)
        let window = WakeWindow.current(startHour: 10, endHour: 2, now: now, calendar: calendar)
        #expect(window.start == TestTime.date(2026, 10, 18, 10))
        #expect(window.end == TestTime.date(2026, 10, 19, 2))
        #expect(window.contains(now))
    }

    @Test("The same From and Until hour means all day")
    func allDay() {
        let window = WakeWindow.current(startHour: 8, endHour: 8, now: TestTime.date(2026, 10, 18, 20), calendar: calendar)
        #expect(window.end.timeIntervalSince(window.start) == 24 * 3600)
    }

    @Test("How far through the day, from 0 to 1")
    func fractionElapsed() {
        let window = WakeWindow.current(startHour: 8, endHour: 20, now: TestTime.date(2026, 10, 18, 14), calendar: calendar)
        #expect(window.fractionElapsed(at: TestTime.date(2026, 10, 18, 14)) == 0.5)
        #expect(window.fractionElapsed(at: TestTime.date(2026, 10, 18, 6)) == 0)
        #expect(window.fractionElapsed(at: TestTime.date(2026, 10, 18, 23)) == 1)
    }
}

@Suite("Pace")
struct PaceTests {
    /// 8 AM to 8 PM; at 2 PM you're halfway through, so you'd have had 1.5 L of a 3 L goal.
    let window = WakeWindow.current(startHour: 8, endHour: 20, now: TestTime.date(2026, 10, 18, 14),
                                    calendar: TestTime.calendar)
    let twoPM = TestTime.date(2026, 10, 18, 14)

    func pace(drank: Int, goal: Int = 3000) -> Pace {
        Pace(drankML: drank, goalML: goal, window: window, now: twoPM)
    }

    @Test("Halfway through the day, you should have drunk half your goal")
    func expected() {
        #expect(pace(drank: 1500).expectedML == 1500)
        #expect(pace(drank: 1500).status == .onTrack)
        #expect(pace(drank: 1500).summary == "On track")
    }

    @Test("Within 5% of the goal (at least 150 ml) still counts as on track")
    func tolerance() {
        #expect(pace(drank: 0, goal: 3000).tolerance == 150)
        #expect(pace(drank: 0, goal: 4000).tolerance == 200)
        #expect(pace(drank: 0, goal: 1000).tolerance == 150)
        #expect(pace(drank: 1650).status == .onTrack)
        #expect(pace(drank: 1350).status == .onTrack)
        #expect(pace(drank: 1651).status == .ahead)
        #expect(pace(drank: 1349).status == .behind)
    }

    @Test("Ahead and behind say by how much")
    func summaries() {
        #expect(pace(drank: 1100).summary == "Behind by 400 ml")
        #expect(pace(drank: 2700).summary == "Ahead by 1.2 L")
        #expect(pace(drank: 1100).difference == -400)
    }

    @Test("Reminders come half as often when ahead, a bit more often when behind")
    func reminderInterval() {
        let thirtyMinutes: TimeInterval = 30 * 60
        #expect(pace(drank: 2700).reminderInterval(base: thirtyMinutes) == 60 * 60)
        #expect(pace(drank: 1500).reminderInterval(base: thirtyMinutes) == 30 * 60)
        #expect(pace(drank: 1100).reminderInterval(base: thirtyMinutes) == 22.5 * 60)
        // Never more often than every 15 minutes.
        #expect(pace(drank: 1100).reminderInterval(base: 16 * 60) == 15 * 60)
    }
}

@Suite("Reminder timing")
struct ReminderTimingTests {
    let window = WakeWindow.current(startHour: 9, endHour: 22, now: TestTime.date(2026, 10, 18, 12),
                                    calendar: TestTime.calendar)
    let thirtyMinutes: TimeInterval = 30 * 60

    func isDue(at hour: Int, _ minute: Int, lastReminder: Date? = nil, lastDrink: Date? = nil) -> Bool {
        ReminderTiming.isDue(now: TestTime.date(2026, 10, 18, hour, minute), window: window,
                             interval: thirtyMinutes, lastReminder: lastReminder, lastDrink: lastDrink)
    }

    @Test("The first reminder comes right as wake hours start")
    func firstOfDay() {
        #expect(isDue(at: 9, 0))
    }

    @Test("No reminders outside wake hours")
    func outsideWakeHours() {
        #expect(!isDue(at: 8, 59))
        #expect(!isDue(at: 22, 30))
    }

    @Test("The next reminder waits a full interval after the last one")
    func afterLastReminder() {
        let nine = TestTime.date(2026, 10, 18, 9)
        #expect(!isDue(at: 9, 20, lastReminder: nine))
        #expect(isDue(at: 9, 30, lastReminder: nine))
    }

    @Test("Logging a drink restarts the clock")
    func drinkRestartsClock() {
        let nine = TestTime.date(2026, 10, 18, 9)
        let drink = TestTime.date(2026, 10, 18, 9, 25)
        #expect(!isDue(at: 9, 30, lastReminder: nine, lastDrink: drink))
        #expect(isDue(at: 9, 55, lastReminder: nine, lastDrink: drink))
    }

    @Test("A drink from last night doesn't hold back the morning's first reminder")
    func yesterdaysDrink() {
        #expect(isDue(at: 9, 0, lastDrink: TestTime.date(2026, 10, 17, 23)))
    }
}
