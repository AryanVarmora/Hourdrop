import SwiftUI
import ServiceManagement

/// Hourdrop's Settings window, in three tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            WaterSettings()
                .tabItem { Label("Water", systemImage: "drop") }
            ReminderSettings()
                .tabItem { Label("Reminders", systemImage: "bell") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
    }
}

// MARK: - Water: what you drink from, goal, water filter

struct WaterSettings: View {
    @ObservedObject private var store = WaterStore.shared
    @AppStorage(Prefs.containerName.key) private var container = Prefs.containerName.fallback
    @AppStorage(Prefs.bottleSizeML.key) private var sizeML = Prefs.bottleSizeML.fallback
    @AppStorage(Prefs.dailyGoalML.key) private var dailyGoalML = Prefs.dailyGoalML.fallback
    @AppStorage(Prefs.filterKind.key) private var filterKind: FilterKind = .none
    @AppStorage(Prefs.filterCustomL.key) private var customL = Prefs.filterCustomL.fallback
    @AppStorage(Prefs.filterCustomMonths.key) private var customMonths = Prefs.filterCustomMonths.fallback
    @AppStorage(Prefs.filterStart.key) private var filterStart = Prefs.filterStart.fallback

    /// Quick picks for the size, by container. Any other size can be typed in.
    private var commonSizes: [(label: String, ml: Int)] {
        if container == "glass" {
            return [8, 10, 12, 16].map { ("\($0) oz glass or cup", Drink.ml(oz: Double($0))) }
        }
        return [16, 20, 24, 32, 40].map { ("\($0) oz bottle", Drink.ml(oz: Double($0))) }
            + [("1 liter bottle", 1000), ("LARQ 25 oz filtered bottle (holds 22.5 oz)", 665)]
    }

    var body: some View {
        Form {
            Section("Water") {
                Picker("I drink from", selection: $container) {
                    Text("A bottle").tag("bottle")
                    Text("A glass or cup").tag("glass")
                }
                SizeRow(label: container == "glass" ? "Glass size" : "Bottle size",
                        value: $sizeML, range: 100...2000, step: 50)
                LabeledContent("Common sizes") {
                    Menu("Choose…") {
                        ForEach(commonSizes, id: \.label) { size in
                            Button("\(size.label) · \(size.ml) ml") { sizeML = size.ml }
                        }
                    }
                    .fixedSize()
                }
                Stepper("Daily goal: \(dailyGoalML) ml (\(Format.ounces(dailyGoalML)))",
                        value: $dailyGoalML, in: 500...6000, step: 250)
            }

            Section {
                Picker("Filter", selection: $filterKind) {
                    ForEach(FilterKind.allCases) { Text($0.label).tag($0) }
                }
                if filterKind == .custom {
                    NumberRow(label: "Lasts up to", value: $customL, range: 0...2000, unit: "liters",
                              note: customL == 0 ? "no liter limit" : nil)
                    NumberRow(label: "or", value: $customMonths, range: 1...24,
                              unit: customMonths == 1 ? "month" : "months")
                }
                if filterKind != .none {
                    DatePicker("Put in on", selection: filterStartDate, in: ...Date.now,
                               displayedComponents: .date)
                    LabeledContent("Used", value: usageText)
                    Button("I replaced it today") { FilterLife.markReplaced() }
                }
            } header: {
                Text("Water filter")
            } footer: {
                Text(filterKind == .none
                     ? "If your bottle or pitcher has a filter, pick it here and Hourdrop will remind you when to change it."
                     : "Hourdrop counts the water you log toward the filter's limit (liters or months, whichever comes first). You get a heads-up at 90%, then a reminder every morning once it's due, until you click Replaced it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: filterKind == .custom ? 590 : 510)
        .onChange(of: sizeML) { NotificationManager.shared.registerButtons() }     // update reminder buttons
        .onChange(of: container) { NotificationManager.shared.registerButtons() }
        .onChange(of: filterKind) {
            if filterKind != .none, filterStart == 0 { filterStart = Date.now.timeIntervalSince1970 }
            resetFilterAlerts()
        }
        // A different filter or date: start its reminders fresh.
        .onChange(of: filterStart) { resetFilterAlerts() }
        .onChange(of: customL) { resetFilterAlerts() }
        .onChange(of: customMonths) { resetFilterAlerts() }
    }

    private func resetFilterAlerts() {
        Prefs.filterAlertedPercent.set(0)
        Prefs.filterRemindedDay.set(0)
    }

    private var filterStartDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: filterStart) },
            set: { filterStart = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
        )
    }

    /// e.g. "23% · 21.6 of 94 L · replace by Dec 18"
    private var usageText: String {
        guard let filter = FilterLife.current() else { return "" }
        let percent = "\(Int(filter.used(now: .now) * 100))%"
        let liters = String(format: "%.1f", Double(filter.filteredML) / 1000)
        let volume = filter.capacityL > 0 ? " · \(liters) of \(filter.capacityL) L" : ""
        return "\(percent)\(volume) · replace by \(filter.replaceBy.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

// MARK: - Reminders: timing and smart behaviour

struct ReminderSettings: View {
    @AppStorage(Prefs.remindersEnabled.key) private var remindersEnabled = Prefs.remindersEnabled.fallback
    @AppStorage(Prefs.reminderIntervalMinutes.key) private var interval = Prefs.reminderIntervalMinutes.fallback
    @AppStorage(Prefs.wakeStartHour.key) private var wakeStartHour = Prefs.wakeStartHour.fallback
    @AppStorage(Prefs.wakeEndHour.key) private var wakeEndHour = Prefs.wakeEndHour.fallback
    @AppStorage(Prefs.adaptToPace.key) private var adaptToPace = Prefs.adaptToPace.fallback
    @AppStorage(Prefs.pauseWhenBusy.key) private var pauseWhenBusy = Prefs.pauseWhenBusy.fallback
    @AppStorage(Prefs.dailyRecap.key) private var dailyRecap = Prefs.dailyRecap.fallback

    var body: some View {
        Form {
            Section {
                Toggle("Remind me", isOn: $remindersEnabled)
                Picker("Every", selection: $interval) {
                    ForEach(NotificationManager.intervalChoices, id: \.self) {
                        Text(Self.intervalLabel($0)).tag($0)
                    }
                }
                Picker("From", selection: $wakeStartHour) {
                    ForEach(0..<24, id: \.self) { Text(Format.hour($0)).tag($0) }
                }
                Picker("Until", selection: $wakeEndHour) {
                    ForEach(0..<24, id: \.self) { Text(Format.hour($0)).tag($0) }
                }
            } footer: {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }

            Section("Smart reminders") {
                Toggle(isOn: $adaptToPace) {
                    Text("Adjust to my pace")
                    Text("Fewer reminders when you're ahead of your goal, more when you're behind.")
                }
                Toggle(isOn: $pauseWhenBusy) {
                    Text("Wait while I'm busy")
                    Text("Holds reminders during calls (any app using a mic), when you're away for 5+ minutes, or when the screen is locked. You get one when you're back.")
                }
                Toggle(isOn: $dailyRecap) {
                    Text("End-of-day recap")
                    Text("A summary of your day when your wake hours end.")
                }
            }

            Section {
                Button("Send a test reminder") { NotificationManager.shared.sendTest() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .onChange(of: remindersEnabled) { NotificationManager.shared.settingsChanged() }
        .onChange(of: interval) { NotificationManager.shared.settingsChanged() }
        .onChange(of: wakeStartHour) { NotificationManager.shared.settingsChanged() }
        .onChange(of: wakeEndHour) { NotificationManager.shared.settingsChanged() }
        .onChange(of: adaptToPace) { NotificationManager.shared.settingsChanged() }
        .onChange(of: pauseWhenBusy) { NotificationManager.shared.settingsChanged() }
    }

    /// e.g. "About every 30 minutes from 9 AM to 10 PM. Logging a drink restarts the clock."
    private var summary: String {
        guard remindersEnabled else { return "Reminders are off." }
        let hours: String
        if wakeStartHour == wakeEndHour {
            hours = "all day"
        } else {
            hours = "from \(Format.hour(wakeStartHour)) to \(Format.hour(wakeEndHour))"
                + (wakeStartHour > wakeEndHour ? " (past midnight)" : "")
        }
        return "About every \(Self.intervalLabel(interval)) \(hours). Logging a drink restarts the clock."
    }

    /// 30 -> "30 minutes", 60 -> "hour", 90 -> "1½ hours", 120 -> "2 hours"
    static func intervalLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: "hour"
        case 90: "1½ hours"
        case let m where m % 60 == 0: "\(m / 60) hours"
        default: "\(minutes) minutes"
        }
    }
}

// MARK: - General: caffeine, keyboard shortcut, launch at login

struct GeneralSettings: View {
    @AppStorage(Prefs.containerName.key) private var container = Prefs.containerName.fallback
    @AppStorage(Prefs.caffeineCutoffHour.key) private var caffeineCutoffHour = Prefs.caffeineCutoffHour.fallback
    @AppStorage(Prefs.shortcutQuarters.key) private var shortcutQuarters = Prefs.shortcutQuarters.fallback
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var shortcutTaken = false

    var body: some View {
        Form {
            Section {
                Picker("Warn me about caffeine after", selection: $caffeineCutoffHour) {
                    Text("Never").tag(-1)
                    ForEach(12...20, id: \.self) { Text(Format.hour($0)).tag($0) }
                }
            } header: {
                Text("Caffeine")
            } footer: {
                Text("Coffee has about 95 mg per 8 oz and chai about 50 mg. Most adults should stay under 400 mg a day, and caffeine late in the day can make it harder to sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("\(HotKey.label) logs", selection: $shortcutQuarters) {
                    Text("Off").tag(0)
                    Text("¼ \(container)").tag(1)
                    Text("½ \(container)").tag(2)
                    Text("Full \(container)").tag(4)
                }
                if shortcutTaken {
                    Text("Another app already uses \(HotKey.label), so this shortcut can't work right now.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Keyboard shortcut")
            } footer: {
                Text("Press \(HotKey.label) (Control-Option-W) in any app to log water without clicking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 350)
        .onAppear { updateShortcutTaken() }
        .onChange(of: shortcutQuarters) {
            HotKey.shared.applyPrefs()
            updateShortcutTaken()
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private func updateShortcutTaken() {
        shortcutTaken = shortcutQuarters > 0 && !HotKey.shared.isRegistered
    }
}

// MARK: - Rows

/// A size you can type exactly (e.g. 665) or nudge with the arrows, with ounces shown.
/// Typed values outside `range` are pulled back inside it.
struct SizeRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("ml (\(Format.ounces(value)))")
                    .foregroundStyle(.secondary)
                Stepper(label, value: clamped, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// A whole number you can type or nudge, with a unit after it, e.g. "150 liters".
struct NumberRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    var note: String? = nil

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(note.map { "\(unit) (\($0))" } ?? unit)
                    .foregroundStyle(.secondary)
                Stepper(label, value: clamped, in: range)
                    .labelsHidden()
            }
        }
    }
}
