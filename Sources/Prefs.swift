import Foundation

/// One saved setting: its key in UserDefaults, and its value until you change it.
struct Pref<Value: Sendable>: Sendable {
    let key: String
    let fallback: Value

    var value: Value { UserDefaults.standard.object(forKey: key) as? Value ?? fallback }
    func set(_ newValue: Value) { UserDefaults.standard.set(newValue, forKey: key) }
}

/// Every setting Sip saves, in one place, so keys and defaults never drift apart.
enum Prefs {
    // Water
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

    // LARQ filter: liters it lasts (0 = not tracking), and when it went in
    static let filterCapacityL = Pref(key: "filterCapacityL", fallback: 94)
    static let filterStart = Pref<Double>(key: "filterStart", fallback: 0)   // seconds since 1970

    // Keyboard shortcut ⌃⌥W: quarters of a bottle to log (0 = off)
    static let shortcutQuarters = Pref(key: "shortcutQuarters", fallback: 1)

    // Bookkeeping, not shown in Settings (all in seconds since 1970)
    static let lastReminderAt = Pref<Double>(key: "lastReminderAt", fallback: 0)
    static let lastRecapFor = Pref<Double>(key: "lastRecapFor", fallback: 0)
    static let caffeineWarnedDay = Pref<Double>(key: "caffeineWarnedDay", fallback: 0)
    static let filterAlertedPercent = Pref(key: "filterAlertedPercent", fallback: 0)
}
