import SwiftUI

@main
struct HourdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WaterStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one Hourdrop at a time: if a copy is already running, this one quits,
        // so you never get two drops in the menu bar or double reminders.
        let me = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me && !$0.isTerminated }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        Prefs.migrate()
        NotificationManager.shared.setUp()

        // ⌃⌥W logs water from anywhere (the amount is set in Settings).
        HotKey.shared.onPress = {
            let quarters = Prefs.shortcutQuarters.value
            guard quarters > 0 else { return }
            let ml = Prefs.bottleSizeML.value * quarters / 4
            WaterStore.shared.add(ml: ml)
            NotificationManager.shared.confirmLogged(ml: ml)
        }
        HotKey.shared.applyPrefs()
    }
}

/// What you see in the menu bar: a drop and today's total, e.g. "💧 1.2 L".
struct MenuBarLabel: View {
    @EnvironmentObject private var store: WaterStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "drop.fill")
            Text(Format.liters(store.todayTotal))
        }
    }
}
