import Foundation
import Testing
@testable import HourdropCore

@Suite("Water filter life")
struct FilterTests {
    let start = TestTime.date(2026, 9, 1)

    func filter(capacityL: Int = 94, months: Int = 2, filteredML: Int = 0) -> FilterLife {
        FilterLife(kind: .larq, start: start, capacityL: capacityL, months: months, filteredML: filteredML)
    }

    @Test("Each filter kind's liters and months")
    func specs() {
        #expect(FilterLife.spec(.none, customL: 150, customMonths: 2) == nil)
        #expect(FilterLife.spec(.larq, customL: 0, customMonths: 0)! == (94, 2))
        #expect(FilterLife.spec(.larqAdvanced, customL: 0, customMonths: 0)! == (151, 2))
        #expect(FilterLife.spec(.custom, customL: 200, customMonths: 6)! == (200, 6))
        // An "Other filter" always lasts at least a month, and never negative liters.
        #expect(FilterLife.spec(.custom, customL: -5, customMonths: 0)! == (0, 1))
    }

    @Test("Used up by volume: 47 L of a 94 L filter is half")
    func byVolume() {
        #expect(filter(filteredML: 47_000).used(now: start) == 0.5)
    }

    @Test("Used up by time: halfway to the replace-by date is half")
    func byTime() {
        let life = filter()
        let halfway = start.addingTimeInterval(life.replaceBy.timeIntervalSince(start) / 2)
        #expect(abs(life.used(now: halfway) - 0.5) < 0.000_1)
    }

    @Test("Whichever runs out first counts")
    func whicheverFirst() {
        let life = filter(filteredML: 84_600)   // 90% by volume, only a few days in
        #expect(abs(life.used(now: start.addingTimeInterval(3 * 86_400)) - 0.9) < 0.000_1)
    }

    @Test("A filter with no liter limit only counts months")
    func noLiterLimit() {
        let life = filter(capacityL: 0, months: 6, filteredML: 500_000)
        #expect(life.used(now: start) == 0)
        #expect(life.limits == "6 months")
    }

    @Test("Limits read naturally")
    func limits() {
        #expect(filter().limits == "2 months or 94 L")
        #expect(filter(months: 1).limits == "1 month or 94 L")
    }

    @Test("Names for messages")
    func names() {
        #expect(FilterKind.larq.title == "LARQ filter")
        #expect(FilterKind.custom.title == "Water filter")
        #expect(FilterKind.custom.name == "water filter")
    }

    // MARK: When to send filter alerts

    let today = TestTime.date(2026, 10, 18).timeIntervalSince1970
    let yesterday = TestTime.date(2026, 10, 17).timeIntervalSince1970

    @Test("A heads-up once at 90%")
    func headsUp() {
        #expect(FilterLife.alertDue(used: 0.89, inWakeHours: true, today: today, remindedDay: 0, alertedPercent: 0) == nil)
        #expect(FilterLife.alertDue(used: 0.92, inWakeHours: true, today: today, remindedDay: 0, alertedPercent: 0) == .headsUp)
        #expect(FilterLife.alertDue(used: 0.95, inWakeHours: true, today: today, remindedDay: 0, alertedPercent: 90) == nil)
    }

    @Test("Once it's due, one reminder a day until replaced")
    func dueDaily() {
        #expect(FilterLife.alertDue(used: 1.0, inWakeHours: true, today: today, remindedDay: yesterday, alertedPercent: 90) == .due)
        #expect(FilterLife.alertDue(used: 1.3, inWakeHours: true, today: today, remindedDay: today, alertedPercent: 90) == nil)
    }

    @Test("No filter alerts outside wake hours")
    func onlyInWakeHours() {
        #expect(FilterLife.alertDue(used: 1.0, inWakeHours: false, today: today, remindedDay: 0, alertedPercent: 0) == nil)
        #expect(FilterLife.alertDue(used: 0.95, inWakeHours: false, today: today, remindedDay: 0, alertedPercent: 0) == nil)
    }
}
