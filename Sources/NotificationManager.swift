import Foundation
import UserNotifications

/// Schedules the reminders and turns the notification buttons into logged water.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let categoryID = "DRINK_REMINDER"

    /// Water buttons on every reminder: parts of your bottle. Read fresh so they follow Settings.
    private static var waterButtons: [(id: String, title: String, ml: Int)] {
        let bottle = UserDefaults.standard.object(forKey: "bottleSizeML") as? Int ?? 750
        return [
            ("LOG_QUARTER", "¼ bottle", bottle / 4),
            ("LOG_HALF", "½ bottle", bottle / 2),
            ("LOG_FULL", "Full bottle", bottle),
        ]
    }

    /// Coffee, chai and smoothie buttons open a box where you type the size.
    private static func drinkID(_ drink: Drink) -> String { "LOG_\(drink.rawValue.uppercased())" }

    /// Choices for how often reminders come, in minutes.
    static let intervalChoices = [30, 60, 90, 120]
    static let defaultInterval = 30

    private let center = UNUserNotificationCenter.current()

    /// Call once at launch.
    func setUp() {
        center.delegate = self
        registerButtons()

        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if granted { scheduleReminders() }
        }
    }

    /// The buttons on every reminder: "¼ bottle (166 ml)" and so on, then "☕️ Coffee…",
    /// which asks how many oz. Call again when the bottle size changes.
    func registerButtons() {
        let water = Self.waterButtons.map {
            UNNotificationAction(identifier: $0.id, title: "\($0.title) (\($0.ml) ml)")
        }
        let drinks = Drink.others.map {
            UNTextInputNotificationAction(
                identifier: Self.drinkID($0),
                title: "\($0.emoji) \($0.name)…",
                options: [],
                textInputButtonTitle: "Log",
                textInputPlaceholder: "How many oz? e.g. 12"
            )
        }
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: water + drinks,
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// One repeating daily reminder for each time slot in your wake hours.
    /// Call again whenever settings change.
    func scheduleReminders() {
        // Clear the old schedule first (it may have used a different interval).
        center.removeAllPendingNotificationRequests()

        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "remindersEnabled") as? Bool ?? true
        let startHour = defaults.object(forKey: "wakeStartHour") as? Int ?? 9
        let endHour = defaults.object(forKey: "wakeEndHour") as? Int ?? 22
        let interval = defaults.object(forKey: "reminderIntervalMinutes") as? Int ?? Self.defaultInterval
        guard enabled else { return }

        for time in Self.reminderTimes(from: startHour, until: endHour, every: interval) {
            var components = DateComponents()
            components.hour = time / 60
            components.minute = time % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "reminder-\(time)",
                content: makeContent(),
                trigger: trigger
            )
            center.add(request)
        }
    }

    /// Reminder times as minutes after midnight, from From through Until, every `interval`
    /// minutes. If Until is earlier than From, the range runs past midnight:
    /// 10 PM until 2 AM every hour gives 10 PM, 11 PM, 12 AM, 1 AM, 2 AM.
    static func reminderTimes(from start: Int, until end: Int, every interval: Int) -> [Int] {
        guard (0..<24).contains(start), (0..<24).contains(end) else { return [] }
        let step = max(interval, 30)   // macOS allows at most 64 scheduled reminders
        let first = start * 60
        let last = (end >= start ? end : end + 24) * 60
        return stride(from: first, through: last, by: step).map { $0 % (24 * 60) }
    }

    /// Fires a reminder 3 seconds from now so you can test the buttons.
    func sendTest() {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(UNNotificationRequest(identifier: "test", content: makeContent(), trigger: trigger))
    }

    private func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time to sip 💧"
        content.body = "Have a drink, then log it under Options."
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        return content
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even while the app is active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A notification button was clicked: log the matching amount.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run { NotificationManager.handle(actionID: actionID, typed: typed) }
    }

    private static func handle(actionID: String, typed: String?) {
        if let button = waterButtons.first(where: { $0.id == actionID }) {
            WaterStore.shared.add(ml: button.ml, drink: .water)
        } else if let drink = Drink.others.first(where: { drinkID($0) == actionID }) {
            if let ml = Drink.ml(fromTyped: typed ?? "") {
                WaterStore.shared.add(ml: ml, drink: drink)
            } else {
                shared.tellCouldNotLog(drink, typed: typed ?? "")
            }
        }
        // Clicking the banner itself or dismissing it matches no button: do nothing.
    }

    /// The typed size wasn't a number we could use, so say so instead of failing silently.
    private func tellCouldNotLog(_ drink: Drink, typed: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(drink.emoji) \(drink.name) not logged"
        content.body = "Couldn't read \"\(typed)\". Type a number of ounces like 12, or log it from the menu bar."
        center.add(UNNotificationRequest(identifier: "not-logged", content: content, trigger: nil))
    }
}
