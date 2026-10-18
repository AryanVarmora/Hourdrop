import SwiftUI
import ServiceManagement

/// Sip's Settings window, in three tabs.
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

// MARK: - Water: bottle, goal, LARQ filter

struct WaterSettings: View {
    @ObservedObject private var store = WaterStore.shared
    @AppStorage(Prefs.bottleSizeML.key) private var bottleSizeML = Prefs.bottleSizeML.fallback
    @AppStorage(Prefs.dailyGoalML.key) private var dailyGoalML = Prefs.dailyGoalML.fallback
    @AppStorage(Prefs.filterCapacityL.key) private var filterCapacityL = Prefs.filterCapacityL.fallback
    @AppStorage(Prefs.filterStart.key) private var filterStart = Prefs.filterStart.fallback

    var body: some View {
        Form {
            Section("Water") {
                SizeRow(label: "Bottle size", value: $bottleSizeML, range: 100...2000, step: 50)
                Stepper("Daily goal: \(dailyGoalML) ml (\(Format.ounces(dailyGoalML)))",
                        value: $dailyGoalML, in: 500...6000, step: 250)
            }

            Section {
                Picker("Filter", selection: $filterCapacityL) {
                    ForEach(FilterLife.capacities, id: \.liters) { Text($0.name).tag($0.liters) }
                    Text("Don't track").tag(0)
                }
                if filterCapacityL > 0 {
                    DatePicker("Put in on", selection: filterStartDate, in: ...Date.now,
                               displayedComponents: .date)
                    LabeledContent("Used", value: usageText)
                    Button("I replaced it today") {
                        filterStart = Date.now.timeIntervalSince1970
                    }
                }
            } header: {
                Text("LARQ filter")
            } footer: {
                Text("Counts the water you log, since it all goes through your bottle's filter. A filter lasts its liters or 2 months, whichever comes first. Sip lets you know at 90% and when it's due.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 430)
        .onChange(of: bottleSizeML) {
            NotificationManager.shared.registerButtons()   // update the ml on reminder buttons
        }
        .onChange(of: filterStart) { Prefs.filterAlertedPercent.set(0) }      // new filter, new alerts
        .onChange(of: filterCapacityL) { Prefs.filterAlertedPercent.set(0) }
    }

    private var filterStartDate: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: filterStart) },
            set: { filterStart = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
        )
    }

    /// e.g. "23% · 21.6 of 94 L · replace by Dec 18"
    private var usageText: String {
        let start = Date(timeIntervalSince1970: filterStart)
        let filter = FilterLife(start: start, capacityL: filterCapacityL,
                                filteredML: store.total(since: start, drink: .water))
        let liters = String(format: "%.1f", Double(filter.filteredML) / 1000)
        return "\(Int(filter.used(now: .now) * 100))% · \(liters) of \(filterCapacityL) L · "
            + "replace by \(filter.replaceBy.formatted(.dateTime.month(.abbreviated).day()))"
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
        .frame(width: 460, height: 520)
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
                    Text("¼ bottle").tag(1)
                    Text("½ bottle").tag(2)
                    Text("Full bottle").tag(4)
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
        .frame(width: 460, height: 350)
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
