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

    /// Whether a drink at `hour` (0 to 23) is late enough for the caffeine heads-up: from the
    /// cutoff hour on, and the small hours before 5 AM count as late too. A cutoff of -1 means never.
    static func isLateForCaffeine(hour: Int, cutoff: Int) -> Bool {
        cutoff >= 0 && (hour >= cutoff || hour < 5)
    }

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
/// ~/Library/Application Support/Hourdrop/water-log.json (full history, not just today),
/// with a daily backup in the Backups folder next to it (see LogBackup).
@MainActor
final class WaterStore: ObservableObject {
    /// The app's store, saving to your real log.
    static let shared = WaterStore(fileURL: realLogURL())

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
    private let backupFolder: URL

    /// Where your drinks are saved: ~/Library/Application Support/Hourdrop/water-log.json.
    /// The app used to be called Sip: the first time, this moves its history over.
    private static func realLogURL() -> URL {
        let files = FileManager.default
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Hourdrop", isDirectory: true)
        let oldDir = support.appendingPathComponent("Sip", isDirectory: true)
        if !files.fileExists(atPath: dir.path),
           files.fileExists(atPath: oldDir.appendingPathComponent("water-log.json").path) {
            try? files.moveItem(at: oldDir, to: dir)
        }
        try? files.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("water-log.json")
    }

    /// The app uses `shared`. Tests make their own store with a file in a temporary
    /// folder, so they can never touch your real log.
    init(fileURL: URL) {
        self.fileURL = fileURL
        backupFolder = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        load()
        LogBackup.makeIfNeeded(of: fileURL, in: backupFolder)

        // Midnight reset: when the day changes, "today" moves forward and the total starts at 0.
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
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
        // Before the day's first change, keep a copy of the log as it was.
        LogBackup.makeIfNeeded(of: fileURL, in: backupFolder)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
