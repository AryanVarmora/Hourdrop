import Foundation

/// A link that logs a drink, so other apps can log for you (Shortcuts, Spencer, scripts):
///   hourdrop://log?ml=250               250 ml of water
///   hourdrop://log?oz=12&drink=coffee   a 12 oz coffee
///   hourdrop://log?bottle=half          half your bottle or glass (quarter, half, full, or a number like 2)
/// It's water unless the link says drink=coffee, drink=chai or drink=smoothie.
struct DrinkLink: Equatable {
    let ml: Int
    let drink: Drink

    /// Works out the drink a link describes. `bottleML` is your bottle (or glass) size from Settings.
    static func parse(_ url: URL, bottleML: Int) -> Result<DrinkLink, LinkError> {
        guard url.host?.lowercased() == "log" else { return .failure(.notALogLink) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value?.trimmingCharacters(in: .whitespaces)
        }

        let drinkName = value("drink")?.lowercased() ?? Drink.water.rawValue
        guard let drink = Drink(rawValue: drinkName) else { return .failure(.unknownDrink(drinkName)) }

        // Exactly one amount: ml, oz or bottle.
        let given = ["ml", "oz", "bottle"].filter { value($0) != nil }
        guard given.count == 1, let unit = given.first, let text = value(unit) else {
            return .failure(given.isEmpty ? .noAmount : .severalAmounts)
        }
        let ml: Double? = switch unit {
        case "ml": Double(text)
        case "oz": Double(text).map { $0 * Drink.mlPerOunce }
        default: bottles(text).map { $0 * Double(bottleML) }
        }
        guard let ml, Drink.sensibleML.contains(ml) else { return .failure(.badAmount(text)) }
        return .success(DrinkLink(ml: Int(ml.rounded()), drink: drink))
    }

    /// "quarter", "half" or "full", or a number of bottles such as 0.5 or 2.
    private static func bottles(_ text: String) -> Double? {
        switch text.lowercased() {
        case "quarter": 0.25
        case "half": 0.5
        case "full": 1
        default: Double(text)
        }
    }

    /// Logs the drink a link describes into `store`, or says what's wrong with the link.
    @MainActor
    static func log(_ url: URL, into store: WaterStore, bottleML: Int) -> Result<DrinkLink, LinkError> {
        let result = parse(url, bottleML: bottleML)
        if case .success(let link) = result {
            store.add(ml: link.ml, drink: link.drink)
        }
        return result
    }
}

/// What's wrong with a link, in words for the "not logged" notification.
enum LinkError: Error, Equatable {
    case notALogLink
    case noAmount
    case severalAmounts
    case badAmount(String)
    case unknownDrink(String)

    var message: String {
        switch self {
        case .notALogLink:
            "Hourdrop links look like hourdrop://log?ml=250."
        case .noAmount:
            "The link needs an amount, like ml=250, oz=12 or bottle=half."
        case .severalAmounts:
            "The link has more than one amount. Use just one of ml, oz or bottle."
        case .badAmount(let text):
            "Couldn't use \"\(text)\" as an amount. It needs to come to between 25 ml and 3 L."
        case .unknownDrink(let name):
            "Hourdrop doesn't know the drink \"\(name)\". Use water, coffee, chai or smoothie."
        }
    }
}
