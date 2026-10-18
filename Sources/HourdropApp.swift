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
    /// Runs before launch finishes, so a link that started Hourdrop isn't missed.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.anotherCopyIsRunning else { return }
        // hourdrop://log?… links from other apps log a drink (see DrinkLink.swift).
        LinkReceiver.shared.onLink = { url in
            switch DrinkLink.log(url, into: WaterStore.shared, bottleML: Prefs.bottleSizeML.value) {
            case .success(let link): NotificationManager.shared.confirmLogged(ml: link.ml, drink: link.drink)
            case .failure(let problem): NotificationManager.shared.tellLinkFailed(problem)
            }
        }
        LinkReceiver.shared.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one Hourdrop at a time: if a copy is already running, this one quits,
        // so you never get two drops in the menu bar or double reminders.
        if Self.anotherCopyIsRunning {
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

    private static var anotherCopyIsRunning: Bool {
        let me = NSRunningApplication.current
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains { $0 != me && !$0.isTerminated }
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
