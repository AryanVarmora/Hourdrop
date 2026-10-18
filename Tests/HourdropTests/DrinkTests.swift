import Foundation
import Testing
@testable import HourdropCore

@Suite("Drink amounts")
struct DrinkAmountTests {
    @Test("Ounces to ml")
    func ouncesToML() {
        #expect(Drink.ml(oz: 8) == 237)
        #expect(Drink.ml(oz: 12) == 355)
        #expect(Drink.ml(oz: 30) == 887)
    }

    @Test("Typed amounts: a plain number means ounces", arguments: [
        ("12", 355), ("12 oz", 355), ("12oz", 355), ("12.5oz", 370), ("  16 ", 473), ("12 OZ", 355),
    ])
    func typedOunces(text: String, ml: Int) {
        #expect(Drink.ml(fromTyped: text) == ml)
    }

    @Test("Typed amounts: \"ml\" means milliliters", arguments: [
        ("355 ml", 355), ("355ml", 355), ("1,000 ml", 1000), ("250 ML", 250),
    ])
    func typedML(text: String, ml: Int) {
        #expect(Drink.ml(fromTyped: text) == ml)
    }

    @Test("Typed amounts that aren't a sensible drink are refused", arguments: [
        "", "abc", "0", "1.2.3", "20 ml", "200", "5000 ml",
    ])
    func typedNonsense(text: String) {
        #expect(Drink.ml(fromTyped: text) == nil)
    }

    @Test("Names and counts")
    func names() {
        #expect(Drink.coffee.name == "Coffee")
        #expect(Drink.coffee.count(1) == "1 coffee")
        #expect(Drink.smoothie.count(3) == "3 smoothies")
    }

    @Test("Older log entries without a drink type were water")
    func oldEntries() {
        #expect(WaterEntry(timestamp: .now, ml: 250, drink: nil).kind == .water)
        #expect(WaterEntry(timestamp: .now, ml: 250, drink: "chai").kind == .chai)
        #expect(WaterEntry(timestamp: .now, ml: 250, drink: "lemonade").kind == .water)
    }
}

@Suite("Caffeine")
struct CaffeineTests {
    @Test("About 95 mg per 8 oz of coffee, 50 mg per 8 oz of chai, none in water or smoothies")
    func perDrink() {
        #expect(Drink.coffee.caffeineMg(ml: 237) == 96)
        #expect(Drink.coffee.caffeineMg(ml: 355) == 144)
        #expect(Drink.chai.caffeineMg(ml: 237) == 48)
        #expect(Drink.water.caffeineMg(ml: 1000) == 0)
        #expect(Drink.smoothie.caffeineMg(ml: 500) == 0)
    }

    @Test("Late caffeine: from the cutoff hour on, and before 5 AM")
    func late() {
        #expect(!Drink.isLateForCaffeine(hour: 13, cutoff: 14))
        #expect(Drink.isLateForCaffeine(hour: 14, cutoff: 14))
        #expect(Drink.isLateForCaffeine(hour: 23, cutoff: 14))
        #expect(Drink.isLateForCaffeine(hour: 3, cutoff: 14))
        #expect(!Drink.isLateForCaffeine(hour: 5, cutoff: 14))
    }

    @Test("A cutoff of Never means no warning at any hour")
    func never() {
        for hour in 0..<24 {
            #expect(!Drink.isLateForCaffeine(hour: hour, cutoff: -1))
        }
    }
}

@Suite("Formatting")
struct FormatTests {
    @Test("Liters and ounces")
    func litersAndOunces() {
        #expect(Format.liters(1234) == "1.2 L")
        #expect(Format.liters(0) == "0.0 L")
        #expect(Format.ounces(665) == "22.5 oz")
    }

    @Test("Small amounts in ml to the nearest 10, bigger ones in liters")
    func amounts() {
        #expect(Format.amount(300) == "300 ml")
        #expect(Format.amount(-300) == "300 ml")
        #expect(Format.amount(304) == "300 ml")
        #expect(Format.amount(305) == "310 ml")
        #expect(Format.amount(1200) == "1.2 L")
    }

    @Test("Hours on a 12-hour clock")
    func hours() {
        #expect(Format.hour(0) == "12 AM")
        #expect(Format.hour(9) == "9 AM")
        #expect(Format.hour(12) == "12 PM")
        #expect(Format.hour(22) == "10 PM")
    }
}
