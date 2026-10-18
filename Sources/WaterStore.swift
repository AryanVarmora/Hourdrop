import Foundation
import Combine

/// What you drank. Everything counts toward your daily total: coffee and tea
/// hydrate about as well as water in normal amounts, and smoothies are mostly water.
enum Drink: String, CaseIterable {
    case water, coffee, chai, smoothie

    /// Drinks you log by size each time (water is logged by bottle instead).
    static let others: [Drink] = [.coffee, .chai, .smoothie]

    /// Quick sizes offered for coffee, chai and smoothies, in US fl oz.
    static let sizesOz: [Double] = [10, 12, 16, 20, 24, 30]

    static let mlPerOunce = 29.5735
    static func ml(oz: Double) -> Int { Int((oz * mlPerOunce).rounded()) }

    /// Turns a typed amount into ml: "12", "12 oz", "12.5oz" are ounces, "355 ml" is ml.
    /// Returns nil for anything that isn't a sensible drink size (about 1 to 100 oz).
    static func ml(fromTyped text: String) -> Int? {
        let lower = text.lowercased().replacingOccurrences(of: ",", with: "")
        guard let value = Double(lower.filter { "0123456789.".contains($0) }), value > 0 else {
            return nil
        }
        let ml = lower.contains("ml") ? value : value * mlPerOunce
        guard (25...3000).contains(ml) else { return nil }
        return Int(ml.rounded())
    }

    var name: String { rawValue.capitalized }

    /// "1 coffee", "2 coffees", "3 smoothies"
    func count(_ n: Int) -> String { "\(n) \(name.lowercased())\(n == 1 ? "" : "s")" }

    /// Rough caffeine per US fl oz: brewed coffee is about 95 mg per 8 oz,
    /// a chai latte about 50 mg per 8 oz.
    var caffeinePerOz: Double {
        switch self {
        case .coffee: 12
        case .chai: 6
        case .water, .smoothie: 0
        }
    }

    func caffeineMg(ml: Int) -> Int { Int((Double(ml) / Self.mlPerOunce * caffeinePerOz).rounded()) }

    var emoji: String {
        switch self {
        case .water: "💧"
        case .coffee: "☕️"
        case .chai: "🍵"
        case .smoothie: "🥤"
        }
    }
}

/// One logged drink. Every tap (menu bar or notification button) creates one of these.
struct WaterEntry: Codable, Identifiable {
    var id = UUID()
    var timestamp: Date
    var ml: Int
    /// "water", "coffee", "chai" or "smoothie". Older entries have none and were water.
    var drink: String?

    var kind: Drink { drink.flatMap(Drink.init(rawValue:)) ?? .water }
}

/// Single source of truth for intake. Saves every drink to
/// ~/Library/Application Support/Sip/water-log.json (full history, not just today).
@MainActor
final class WaterStore: ObservableObject {
    static let shared = WaterStore()

    @Published private(set) var entries: [WaterEntry] = []
    @Published private(set) var dayStart = Calendar.current.startOfDay(for: .now)

    var todayEntries: [WaterEntry] { entries.filter { $0.timestamp >= dayStart } }
    var todayTotal: Int { todayEntries.reduce(0) { $0 + $1.ml } }

    var todayCaffeineMg: Int { caffeineMg(since: dayStart) }
    var lastDrinkAt: Date? { entries.map(\.timestamp).max() }

    /// Sends each new drink right after it's logged (used for the late-caffeine nudge).
    let drinkLogged = PassthroughSubject<WaterEntry, Never>()

    /// Total ml since `start`, for one drink or for everything.
    func total(since start: Date, drink: Drink? = nil) -> Int {
        entries.filter { $0.timestamp >= start && (drink == nil || $0.kind == drink) }
            .reduce(0) { $0 + $1.ml }
    }

    func caffeineMg(since start: Date) -> Int {
        entries.filter { $0.timestamp >= start }.reduce(0) { $0 + $1.kind.caffeineMg(ml: $1.ml) }
    }

    /// How many of each drink since `start`, e.g. 2 coffees and 1 smoothie.
    func counts(since start: Date) -> [(drink: Drink, count: Int)] {
        Drink.allCases.compactMap { drink in
            let n = entries.filter { $0.timestamp >= start && $0.kind == drink }.count
            return n > 0 ? (drink, n) : nil
        }
    }

    /// Today's total for each drink you've had, e.g. water 1300, coffee 355.
    var todayByDrink: [(drink: Drink, ml: Int)] {
        Drink.allCases.compactMap { drink in
            let ml = todayEntries.filter { $0.kind == drink }.reduce(0) { $0 + $1.ml }
            return ml > 0 ? (drink, ml) : nil
        }
    }

    private let fileURL: URL

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sip", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("water-log.json")
        load()

        // Midnight reset: when the day changes, "today" moves forward and the total starts at 0.
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { WaterStore.shared.refresh() }
        }
    }

    func add(ml: Int, drink: Drink = .water) {
        guard ml > 0 else { return }
        refresh()
        let entry = WaterEntry(timestamp: .now, ml: ml, drink: drink.rawValue)
        entries.append(entry)
        save()
        drinkLogged.send(entry)
    }

    func undoLast() {
        guard let last = todayEntries.last else { return }
        entries.removeAll { $0.id == last.id }
        save()
    }

    func refresh() {
        let start = Calendar.current.startOfDay(for: .now)
        if start != dayStart { dayStart = start }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([WaterEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
