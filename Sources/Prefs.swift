import Foundation

/// One saved setting: its key in UserDefaults, and its value until you change it.
struct Pref<Value: Sendable>: Sendable {
    let key: String
    let fallback: Value

    var value: Value { UserDefaults.standard.object(forKey: key) as? Value ?? fallback }
    func set(_ newValue: Value) { UserDefaults.standard.set(newValue, forKey: key) }
}

/// Every setting Hourdrop saves, in one place, so keys and defaults never drift apart.
enum Prefs {
    // Water: what you drink from ("bottle" or "glass") and how much it holds
    static let containerName = Pref(key: "containerName", fallback: "bottle")
    static let bottleSizeML = Pref(key: "bottleSizeML", fallback: 750)
    static let dailyGoalML = Pref(key: "dailyGoalML", fallback: 3000)

    // Reminders
    static let remindersEnabled = Pref(key: "remindersEnabled", fallback: true)
    static let reminderIntervalMinutes = Pref(key: "reminderIntervalMinutes", fallback: 30)
    static let wakeStartHour = Pref(key: "wakeStartHour", fallback: 9)
    static let wakeEndHour = Pref(key: "wakeEndHour", fallback: 22)
    static let adaptToPace = Pref(key: "adaptToPace", fallback: true)
    static let pauseWhenBusy = Pref(key: "pauseWhenBusy", fallback: true)
    static let dailyRecap = Pref(key: "dailyRecap", fallback: true)

    // Caffeine: warn about coffee or chai from this hour on (-1 = off)
    static let caffeineCutoffHour = Pref(key: "caffeineCutoffHour", fallback: 14)

    // Water filter: which one (a FilterKind), an "Other filter"'s limits, and when it went in
    static let filterKind = Pref(key: "filterKind", fallback: FilterKind.none.rawValue)
    static let filterCustomL = Pref(key: "filterCustomL", fallback: 150)        // 0 = no liter limit
    static let filterCustomMonths = Pref(key: "filterCustomMonths", fallback: 2)
    static let filterStart = Pref<Double>(key: "filterStart", fallback: 0)       // seconds since 1970

    // Keyboard shortcut ⌃⌥W: quarters of a bottle to log (0 = off)
    static let shortcutQuarters = Pref(key: "shortcutQuarters", fallback: 1)

    // Bookkeeping, not shown in Settings (all in seconds since 1970)
    static let lastReminderAt = Pref<Double>(key: "lastReminderAt", fallback: 0)
    static let lastRecapFor = Pref<Double>(key: "lastRecapFor", fallback: 0)
    static let caffeineWarnedDay = Pref<Double>(key: "caffeineWarnedDay", fallback: 0)
    static let filterAlertedPercent = Pref(key: "filterAlertedPercent", fallback: 0)   // 90 once the heads-up went out
    static let filterRemindedDay = Pref<Double>(key: "filterRemindedDay", fallback: 0)  // last day a "change it" reminder went out

    /// One-time upgrade of settings saved by older versions. Earlier versions always
    /// tracked a LARQ filter, so anyone who ran one keeps LARQ tracking; new people start with none.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: filterKind.key) == nil else { return }
        let oldCapacity = defaults.object(forKey: "filterCapacityL") as? Int ?? 94
        let kind: FilterKind
        if filterStart.value == 0 || oldCapacity == 0 {
            kind = .none
        } else {
            kind = oldCapacity == 151 ? .larqAdvanced : .larq
        }
        filterKind.set(kind.rawValue)
        defaults.removeObject(forKey: "filterCapacityL")
    }
}
