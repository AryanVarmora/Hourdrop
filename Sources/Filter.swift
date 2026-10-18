import Foundation

/// Your LARQ bottle filter. It lasts a set number of liters (94 L standard,
/// 151 L Advanced) or 2 months, whichever comes first.
struct FilterLife {
    static let lifetimeMonths = 2
    /// The choices in Settings: liters per filter (0 = not tracking).
    static let capacities = [(liters: 94, name: "Standard (94 L)"), (liters: 151, name: "Advanced (151 L)")]

    let start: Date
    let capacityL: Int
    let filteredML: Int   // water logged since the filter went in

    /// When the 2 months are up.
    var replaceBy: Date {
        Calendar.current.date(byAdding: .month, value: Self.lifetimeMonths, to: start)!
    }

    /// How used up the filter is: 0 = new, 1 = due. The larger of volume and time.
    func used(now: Date) -> Double {
        let byVolume = capacityL > 0 ? Double(filteredML) / Double(capacityL * 1000) : 0
        let lifetime = replaceBy.timeIntervalSince(start)
        let byTime = lifetime > 0 ? now.timeIntervalSince(start) / lifetime : 0
        return max(byVolume, byTime, 0)
    }

    /// The current filter from Settings, or nil if you've turned tracking off.
    @MainActor
    static func current() -> FilterLife? {
        let capacity = Prefs.filterCapacityL.value
        guard capacity > 0 else { return nil }
        let start = Date(timeIntervalSince1970: Prefs.filterStart.value)
        return FilterLife(start: start, capacityL: capacity,
                          filteredML: WaterStore.shared.total(since: start, drink: .water))
    }
}
