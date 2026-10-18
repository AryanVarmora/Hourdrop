import AppKit
import Combine
import UserNotifications

/// Decides when to remind you, posts every Sip notification, and turns reminder buttons
/// into logged drinks. Sip checks once a minute instead of using a fixed schedule, so it can
/// wait while you're busy, space reminders by your pace, and send an end-of-day recap.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private static let categoryID = "DRINK_REMINDER"

    /// Choices for how often reminders come, in minutes.
    static let intervalChoices = [30, 60, 90, 120]

    private let center = UNUserNotificationCenter.current()
    private var timer: Timer?
    private var drinkWatcher: AnyCancellable?
    /// Keeps macOS from napping Sip in the background, which would delay reminders.
    private var activity: NSObjectProtocol?

    /// Water buttons on every reminder: parts of your bottle. Read fresh so they follow Settings.
    private static var waterButtons: [(id: String, title: String, ml: Int)] {
        let bottle = Prefs.bottleSizeML.value
        return [
            ("LOG_QUARTER", "¼ bottle", bottle / 4),
            ("LOG_HALF", "½ bottle", bottle / 2),
            ("LOG_FULL", "Full bottle", bottle),
        ]
    }

    /// Coffee, chai and smoothie buttons open a box where you type the size.
    private static func drinkID(_ drink: Drink) -> String { "LOG_\(drink.rawValue.uppercased())" }

    // MARK: - Setup

    /// Call once at launch.
    func setUp() {
        center.delegate = self
        registerButtons()
        // Older versions scheduled reminders ahead of time; clear any that are left.
        center.removeAllPendingNotificationRequests()

        // Start counting filter use from today until you set the real date in Settings.
        if Prefs.filterStart.value == 0 { Prefs.filterStart.set(Date.now.timeIntervalSince1970) }

        drinkWatcher = WaterStore.shared.drinkLogged.sink { entry in
            MainActor.assumeIsolated { NotificationManager.shared.checkLateCaffeine(entry) }
        }

        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Timing water reminders")
        startTimer()

        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            check()
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

    private func startTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { NotificationManager.shared.check() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Check straight away when the Mac wakes up or you unlock it.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotificationManager.shared.check() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotificationManager.shared.check() }
        }
    }

    /// Call when a reminder setting changes, so it takes effect right away.
    func settingsChanged() { check() }

    // MARK: - The once-a-minute check

    /// Sends whatever is due: a reminder, the end-of-day recap, or a filter alert.
    /// If you're busy (call, away, screen locked), it waits and tries again next minute,
    /// so you get one reminder when you're back instead of a pile.
    func check(now: Date = .now) {
        let window = WakeWindow.fromPrefs(now: now)
        let pace = currentPace(window: window, now: now)
        let reminderDue = Prefs.remindersEnabled.value && ReminderTiming.isDue(
            now: now, window: window,
            interval: reminderInterval(for: pace),
            lastReminder: Self.date(Prefs.lastReminderAt.value),
            lastDrink: WaterStore.shared.lastDrinkAt
        )
        let recapDue = recapIsDue(window: window, now: now)
        let filterAlert = dueFilterAlert(now: now)

        guard reminderDue || recapDue || filterAlert != nil else { return }
        if Prefs.pauseWhenBusy.value, Presence.busyReason() != nil { return }

        if reminderDue {
            post("reminder", reminderContent(pace))
            Prefs.lastReminderAt.set(now.timeIntervalSince1970)
        }
        if recapDue {
            post("recap", recapContent(window: window))
            Prefs.lastRecapFor.set(window.start.timeIntervalSince1970)
        }
        if let filterAlert {
            post("filter", filterAlert.content)
            Prefs.filterAlertedPercent.set(filterAlert.percent)
        }
    }

    func currentPace(window: WakeWindow, now: Date = .now) -> Pace {
        Pace(drankML: WaterStore.shared.total(since: window.start),
             goalML: Prefs.dailyGoalML.value, window: window, now: now)
    }

    private func reminderInterval(for pace: Pace) -> TimeInterval {
        let base = TimeInterval(Prefs.reminderIntervalMinutes.value * 60)
        return Prefs.adaptToPace.value ? pace.reminderInterval(base: base) : base
    }

    private static func date(_ secondsSince1970: Double) -> Date? {
        secondsSince1970 > 0 ? Date(timeIntervalSince1970: secondsSince1970) : nil
    }

    // MARK: - What each notification says

    private func reminderContent(_ pace: Pace) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time to sip 💧"
        switch pace.status {
        case .behind:
            content.body = "You're \(Format.amount(pace.difference)) behind. Have a drink, then log it under Options."
        case .ahead:
            content.body = "You're ahead of pace, nice. Have a sip, then log it under Options."
        case .onTrack:
            content.body = "You're on track. Have a drink, then log it under Options."
        }
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        return content
    }

    /// The recap goes out once, within 2 hours after your wake hours end
    /// (so a Mac that slept through it doesn't send yesterday's recap the next morning).
    private func recapIsDue(window: WakeWindow, now: Date) -> Bool {
        Prefs.dailyRecap.value
            && now > window.end
            && now.timeIntervalSince(window.end) < 2 * 3600
            && Prefs.lastRecapFor.value != window.start.timeIntervalSince1970
    }

    /// e.g. "Today: 3.2 L of 4.0 L 💧" / "💧 2.4 L water · ☕️ 2 coffees · ~190 mg caffeine"
    private func recapContent(window: WakeWindow) -> UNMutableNotificationContent {
        let store = WaterStore.shared
        let total = store.total(since: window.start)
        let goal = Prefs.dailyGoalML.value
        let content = UNMutableNotificationContent()
        content.title = total >= goal
            ? "Goal reached 🎉 \(Format.liters(total)) today"
            : "Today: \(Format.liters(total)) of \(Format.liters(goal)) 💧"
        var parts = store.counts(since: window.start).map { item in
            item.drink == .water
                ? "💧 \(Format.liters(store.total(since: window.start, drink: .water))) water"
                : "\(item.drink.emoji) \(item.drink.count(item.count))"
        }
        let caffeine = store.caffeineMg(since: window.start)
        if caffeine > 0 { parts.append("~\(caffeine) mg caffeine") }
        content.body = parts.isEmpty ? "Nothing logged today. Tomorrow's a fresh start." : parts.joined(separator: " · ")
        return content
    }

    /// A heads-up at 90% and a reminder at 100%, once each per filter.
    private func dueFilterAlert(now: Date) -> (content: UNMutableNotificationContent, percent: Int)? {
        guard let filter = FilterLife.current() else { return nil }
        let percent = Int(filter.used(now: now) * 100)
        let alerted = Prefs.filterAlertedPercent.value
        let content = UNMutableNotificationContent()
        if percent >= 100, alerted < 100 {
            content.title = "Time to replace your LARQ filter"
            content.body = "It's used up (2 months or \(filter.capacityL) L). After swapping it, open Sip Settings → Water → I replaced it."
            return (content, 100)
        }
        if percent >= 90, alerted < 90 {
            content.title = "LARQ filter almost used up"
            content.body = "It's at \(percent)%. Plan to replace it by \(filter.replaceBy.formatted(date: .abbreviated, time: .omitted))."
            return (content, 90)
        }
        return nil
    }

    /// After a coffee or chai late in the day, one heads-up per day about sleep.
    private func checkLateCaffeine(_ entry: WaterEntry) {
        let cutoff = Prefs.caffeineCutoffHour.value
        guard cutoff >= 0, entry.kind.caffeinePerOz > 0 else { return }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: entry.timestamp)
        guard hour >= cutoff || hour < 5 else { return }
        let day = calendar.startOfDay(for: entry.timestamp).timeIntervalSince1970
        guard Prefs.caffeineWarnedDay.value != day else { return }
        Prefs.caffeineWarnedDay.set(day)

        let content = UNMutableNotificationContent()
        content.title = "☕️ Late caffeine"
        content.body = "Caffeine after \(Format.hour(cutoff)) can make it harder to fall asleep. "
            + "You've had about \(WaterStore.shared.todayCaffeineMg) mg today."
        post("caffeine", content)
    }

    /// Quiet confirmation after the keyboard shortcut logs water.
    func confirmLogged(ml: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Logged \(ml) ml 💧"
        content.body = "Today: \(Format.liters(WaterStore.shared.todayTotal)) of \(Format.liters(Prefs.dailyGoalML.value))"
        post("logged", content)
    }

    /// Fires a reminder 3 seconds from now so you can test the buttons.
    func sendTest() {
        let pace = currentPace(window: WakeWindow.fromPrefs())
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(UNNotificationRequest(identifier: "test", content: reminderContent(pace), trigger: trigger))
    }

    /// Shows a notification now. Reusing an id replaces the older one, so they don't pile up.
    private func post(_ id: String, _ content: UNMutableNotificationContent) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
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
        post("not-logged", content)
    }
}
