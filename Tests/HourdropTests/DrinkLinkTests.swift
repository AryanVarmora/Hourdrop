import Foundation
import Testing
@testable import HourdropCore

@Suite("hourdrop:// links")
struct DrinkLinkTests {
    /// Reads a link with a 750 ml bottle.
    func parse(_ link: String) -> Result<DrinkLink, LinkError> {
        DrinkLink.parse(URL(string: link)!, bottleML: 750)
    }

    @Test("Links that log a drink", arguments: [
        ("hourdrop://log?ml=250", 250, Drink.water),
        ("hourdrop://log?ml=250&drink=water", 250, .water),
        ("hourdrop://log?oz=12&drink=coffee", 355, .coffee),
        ("hourdrop://log?drink=chai&oz=8", 237, .chai),
        ("hourdrop://log?oz=16.5&drink=smoothie", 488, .smoothie),
        ("hourdrop://log?bottle=quarter", 188, .water),
        ("hourdrop://log?bottle=half", 375, .water),
        ("hourdrop://log?bottle=full", 750, .water),
        ("hourdrop://log?bottle=2", 1500, .water),
        ("hourdrop://log?bottle=0.5", 375, .water),
        ("HOURDROP://LOG?ML=300&DRINK=Coffee", 300, .coffee),
        ("hourdrop://log?ml=%20300%20", 300, .water),
    ])
    func works(link: String, ml: Int, drink: Drink) {
        #expect(parse(link) == .success(DrinkLink(ml: ml, drink: drink)))
    }

    @Test("Links that are refused, with the reason", arguments: [
        ("hourdrop://open?ml=250", LinkError.notALogLink),
        ("hourdrop://log", .noAmount),
        ("hourdrop://log?drink=coffee", .noAmount),
        ("hourdrop://log?ml=250&oz=8", .severalAmounts),
        ("hourdrop://log?ml=abc", .badAmount("abc")),
        ("hourdrop://log?ml=", .badAmount("")),
        ("hourdrop://log?ml=10", .badAmount("10")),
        ("hourdrop://log?ml=-250", .badAmount("-250")),
        ("hourdrop://log?ml=5000", .badAmount("5000")),
        ("hourdrop://log?oz=nan", .badAmount("nan")),
        ("hourdrop://log?bottle=10", .badAmount("10")),
        ("hourdrop://log?bottle=lots", .badAmount("lots")),
        ("hourdrop://log?ml=250&drink=beer", .unknownDrink("beer")),
    ])
    func refused(link: String, problem: LinkError) {
        #expect(parse(link) == .failure(problem))
    }

    @Test("Bottle amounts follow your bottle size from Settings")
    func bottleSize() {
        let link = URL(string: "hourdrop://log?bottle=half")!
        #expect(DrinkLink.parse(link, bottleML: 665) == .success(DrinkLink(ml: 333, drink: .water)))
    }

    @Test("Every problem has a message to show")
    func messages() {
        let problems: [LinkError] = [.notALogLink, .noAmount, .severalAmounts, .badAmount("x"), .unknownDrink("beer")]
        for problem in problems {
            #expect(!problem.message.isEmpty)
        }
        #expect(LinkError.unknownDrink("beer").message.contains("beer"))
    }

    @Test("A good link is logged; a bad one logs nothing")
    @MainActor
    func logsIntoStore() throws {
        let store = WaterStore(fileURL: try makeTempFolder().appendingPathComponent("water-log.json"))
        _ = DrinkLink.log(URL(string: "hourdrop://log?oz=12&drink=coffee")!, into: store, bottleML: 750)
        _ = DrinkLink.log(URL(string: "hourdrop://log?ml=abc")!, into: store, bottleML: 750)
        #expect(store.todayEntries.map(\.ml) == [355])
        #expect(store.todayEntries.map(\.kind) == [.coffee])
    }
}
