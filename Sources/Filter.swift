import Foundation

/// Which water filter you use, if any. Most bottles don't have one, so None is the default.
enum FilterKind: String, CaseIterable, Identifiable {
    case none, larq, larqAdvanced, custom

    var id: String { rawValue }

    /// For the Settings picker.
    var label: String {
        switch self {
        case .none: "None"
        case .larq: "LARQ bottle filter (94 L or 2 months)"
        case .larqAdvanced: "LARQ Advanced filter (151 L or 2 months)"
        case .custom: "Other filter"
        }
    }

    /// For messages: "Time to change your LARQ filter".
    var name: String {
        switch self {
        case .larq, .larqAdvanced: "LARQ filter"
        case .none, .custom: "water filter"
        }
    }

    /// The name at the start of a sentence: "LARQ filter", "Water filter".
    var title: String { name.prefix(1).uppercased() + name.dropFirst() }
}

/// Your water filter's life: it lasts a number of liters or months, whichever comes first.
struct FilterLife {
    let kind: FilterKind
    let start: Date
    let capacityL: Int   // 0 = no liter limit (only months count)
    let months: Int
    let filteredML: Int  // water logged since the filter went in

    var name: String { kind.name }

    /// When the months are up.
    var replaceBy: Date {
        Calendar.current.date(byAdding: .month, value: max(months, 1), to: start)!
    }

    /// e.g. "2 months or 94 L", or "6 months" for a filter with no liter limit.
    var limits: String {
        let time = "\(months) month\(months == 1 ? "" : "s")"
        return capacityL > 0 ? "\(time) or \(capacityL) L" : time
    }

    /// How used up the filter is: 0 = new, 1 = due. The larger of volume and time.
    func used(now: Date) -> Double {
        let byVolume = capacityL > 0 ? Double(filteredML) / Double(capacityL * 1000) : 0
        let lifetime = replaceBy.timeIntervalSince(start)
        let byTime = lifetime > 0 ? now.timeIntervalSince(start) / lifetime : 0
        return max(byVolume, byTime, 0)
    }

    /// Liters and months for a filter kind (nil for None).
    static func spec(_ kind: FilterKind, customL: Int, customMonths: Int) -> (liters: Int, months: Int)? {
        switch kind {
        case .none: nil
        case .larq: (94, 2)
        case .larqAdvanced: (151, 2)
        case .custom: (max(customL, 0), max(customMonths, 1))
        }
    }

    enum Alert: Equatable {
        case headsUp   // 90% used: once per filter
        case due       // used up: once a day until you replace it
    }

    /// Which filter notification to send now, if any. Only during wake hours, so the
    /// daily "change it" reminder comes in the morning, not overnight.
    static func alertDue(used: Double, inWakeHours: Bool, today: Double,
                         remindedDay: Double, alertedPercent: Int) -> Alert? {
        guard inWakeHours else { return nil }
        if used >= 1 { return remindedDay == today ? nil : .due }
        if used >= 0.9, alertedPercent < 90 { return .headsUp }
        return nil
    }

    /// You put in a new filter: count from now and reset the reminders.
    @MainActor
    static func markReplaced(now: Date = .now) {
        Prefs.filterStart.set(now.timeIntervalSince1970)
        Prefs.filterAlertedPercent.set(0)
        Prefs.filterRemindedDay.set(0)
    }

    /// Your filter from Settings, or nil if you don't use one.
    @MainActor
    static func current() -> FilterLife? {
        let kind = FilterKind(rawValue: Prefs.filterKind.value) ?? .none
        guard let spec = spec(kind, customL: Prefs.filterCustomL.value,
                              customMonths: Prefs.filterCustomMonths.value) else { return nil }
        let start = Date(timeIntervalSince1970: Prefs.filterStart.value)
        return FilterLife(kind: kind, start: start, capacityL: spec.liters, months: spec.months,
                          filteredML: WaterStore.shared.total(since: start, drink: .water))
    }
}
