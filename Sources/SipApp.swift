import SwiftUI

@main
struct SipApp: App {
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
        // Only one Sip at a time: if a copy is already running, this one quits,
        // so you never get two drops in the menu bar or double reminders.
        let me = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me && !$0.isTerminated }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        NotificationManager.shared.setUp()
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

enum Format {
    static func liters(_ ml: Int) -> String {
        String(format: "%.1f L", Double(ml) / 1000)
    }

    /// US fluid ounces, e.g. 665 ml -> "22.5 oz".
    static func ounces(_ ml: Int) -> String {
        String(format: "%.1f oz", Double(ml) / 29.5735)
    }
}
