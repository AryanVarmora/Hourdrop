import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("bottleSizeML") private var bottleSizeML = 750
    @AppStorage("dailyGoalML") private var dailyGoalML = 3000
    @AppStorage("remindersEnabled") private var remindersEnabled = true
    @AppStorage("reminderIntervalMinutes") private var reminderInterval = 30
    @AppStorage("wakeStartHour") private var wakeStartHour = 9
    @AppStorage("wakeEndHour") private var wakeEndHour = 22
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Water") {
                sizeRow("Bottle size", $bottleSizeML, range: 100...2000, step: 50)
                Stepper("Daily goal: \(dailyGoalML) ml", value: $dailyGoalML, in: 500...6000, step: 250)
            }

            Section("Reminders") {
                Toggle("Remind me", isOn: $remindersEnabled)
                Picker("Every", selection: $reminderInterval) {
                    ForEach(NotificationManager.intervalChoices, id: \.self) {
                        Text(intervalLabel($0)).tag($0)
                    }
                }
                Picker("From", selection: $wakeStartHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Until", selection: $wakeEndHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                if remindersEnabled {
                    Text(reminderSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Send a test reminder") {
                    NotificationManager.shared.sendTest()
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onChange(of: bottleSizeML) {
            NotificationManager.shared.registerButtons()   // update the ml on reminder buttons
        }
        .onChange(of: remindersEnabled) { NotificationManager.shared.scheduleReminders() }
        .onChange(of: reminderInterval) { NotificationManager.shared.scheduleReminders() }
        .onChange(of: wakeStartHour) { NotificationManager.shared.scheduleReminders() }
        .onChange(of: wakeEndHour) { NotificationManager.shared.scheduleReminders() }
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

    /// A size you can type exactly (e.g. 665) or nudge with the arrows, with ounces shown.
    /// Typed values outside `range` are pulled back inside it.
    private func sizeRow(_ label: String, _ value: Binding<Int>,
                         range: ClosedRange<Int>, step: Int) -> some View {
        let clamped = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
        return LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("ml (\(Format.ounces(value.wrappedValue)))")
                    .foregroundStyle(.secondary)
                Stepper(label, value: clamped, in: range, step: step)
                    .labelsHidden()
            }
        }
    }

    /// e.g. "27 reminders a day." or "9 reminders a day, past midnight until 2 AM."
    private var reminderSummary: String {
        let count = NotificationManager.reminderTimes(
            from: wakeStartHour, until: wakeEndHour, every: reminderInterval
        ).count
        let perDay = "\(count) reminder\(count == 1 ? "" : "s") a day"
        if wakeStartHour > wakeEndHour {
            return "\(perDay), past midnight until \(hourLabel(wakeEndHour))."
        }
        return "\(perDay)."
    }

    /// 30 -> "30 minutes", 60 -> "1 hour", 90 -> "1½ hours"
    private func intervalLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "1 hour"
        case 90: return "1½ hours"
        case let m where m % 60 == 0: return "\(m / 60) hours"
        default: return "\(minutes) minutes"
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(hour < 12 ? "AM" : "PM")"
    }
}
