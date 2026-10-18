import SwiftUI

// Takes the README screenshots. Built by Tools/screenshots.sh together with the app's own
// Sources (all but HourdropApp.swift), so the popover and Settings are the real views.
// It fills them with made-up demo data and runs as a separate app, so your own drinks and
// settings are never read or changed.

@main
struct ScreenshotApp: App {
    @NSApplicationDelegateAdaptor(Shooter.self) private var shooter
    @StateObject private var store: WaterStore

    init() {
        Demo.setUp()   // before WaterStore.shared loads the log
        _store = StateObject(wrappedValue: WaterStore.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "drop.fill")
                Text(Format.liters(store.todayTotal))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Made-up drinks and settings: a 750 ml bottle, a 3 L goal, a LARQ filter put in 18 days ago,
/// and today's drinks spread from 9 AM until now so the pace reads "On track".
enum Demo {
    static func setUp() {
        // Refuse to run as the real app or in your real home folder.
        let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        guard Bundle.main.bundleIdentifier != "com.aryanvarmora.sip", NSHomeDirectory() != realHome else {
            print("Run this through Tools/screenshots.sh, which uses a temporary home folder.")
            exit(1)
        }

        let calendar = Calendar.current
        let now = Date.now
        let wakeStart = 9, wakeEnd = 22
        let defaults = UserDefaults.standard
        let settings: [String: Any] = [
            Prefs.containerName.key: "bottle",
            Prefs.bottleSizeML.key: 750,
            Prefs.dailyGoalML.key: 3000,
            Prefs.wakeStartHour.key: wakeStart,
            Prefs.wakeEndHour.key: wakeEnd,
            Prefs.filterKind.key: FilterKind.larq.rawValue,
            Prefs.filterStart.key: calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: -18, to: now)!).timeIntervalSince1970,
        ]
        for (key, value) in settings { defaults.set(value, forKey: key) }

        var entries: [WaterEntry] = []
        // The last 18 days: about 2.5 L of water a day, so the filter shows some use.
        for daysAgo in 1...18 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            for hour in stride(from: 10, through: 20, by: 2) {
                entries.append(WaterEntry(timestamp: day.addingTimeInterval(Double(hour) * 3600),
                                          ml: 415, drink: Drink.water.rawValue))
            }
        }
        // Today: a 12 oz coffee in the morning, then half bottles until you're on pace.
        let window = WakeWindow.current(startHour: wakeStart, endHour: wakeEnd, now: now)
        if window.contains(now) {
            let expected = Int(3000 * window.fractionElapsed(at: now))
            var time = window.start.addingTimeInterval(20 * 60)
            entries.append(WaterEntry(timestamp: time, ml: Drink.ml(oz: 12), drink: Drink.coffee.rawValue))
            var total = Drink.ml(oz: 12)
            let gap = max(now.timeIntervalSince(time) / Double(max(expected / 375, 1)), 60)
            while total + 375 <= expected + 100 {
                time = time.addingTimeInterval(gap)
                if time > now.addingTimeInterval(-5 * 60) { break }
                entries.append(WaterEntry(timestamp: time, ml: 375, drink: Drink.water.rawValue))
                total += 375
            }
        } else {
            print("Note: it's outside the demo's wake hours (9 AM to 10 PM), so the pace line won't show.")
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Hourdrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try! encoder.encode(entries).write(to: dir.appendingPathComponent("water-log.json"))
    }
}

/// Takes each Settings tab, then waits for you to click the demo drop in the menu bar and
/// takes the popover. (macOS doesn't let an app open its own menu bar popover from code.)
@MainActor
final class Shooter: NSObject, NSApplicationDelegate {
    private let outputDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ".")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IOLBF, 0)   // show each message as soon as it's printed
        NSApp.appearance = NSAppearance(named: .aqua)   // light mode, for consistent images
        HotKey.shared.register()   // so Settings doesn't say the shortcut is taken
        // Safety net: never leave a stuck demo app behind.
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
            print("Timed out.")
            exit(1)
        }
        Task { await run() }
    }

    private func run() async {
        await pause(1)

        // Settings: the app menu's "Settings…" item, then each tab in turn.
        NSApp.activate()
        guard let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }),
              let menu = item.menu else { return quit("Couldn't find the Settings… menu item.") }
        menu.performActionForItem(at: menu.index(of: item))
        await pause(1.5)
        guard let settings = NSApp.windows.first(where: {
            $0.isVisible && $0.toolbar?.items.contains { $0.label == "Water" } == true
        }), let toolbar = settings.toolbar else { return quit("Settings didn't open.") }
        // Each tab is a toolbar button: select it the way a click does.
        for tab in ["Water", "Reminders", "General"] {
            guard let item = toolbar.items.first(where: { $0.label == tab }), let action = item.action else {
                return quit("Couldn't find the \(tab) tab.")
            }
            toolbar.selectedItemIdentifier = item.itemIdentifier
            NSApp.sendAction(action, to: item.target, from: item)
            await pause(1.2)   // the window animates to the tab's height
            await bringToFront(settings)
            settings.makeFirstResponder(nil)   // no text box selected
            await pause(0.3)
            save(settings, as: "settings-\(tab.lowercased())")
        }
        settings.close()
        if ProcessInfo.processInfo.environment["SETTINGS_ONLY"] == "1" { return quit(nil) }

        // The popover: wait up to a minute for a click on the demo drop.
        print("Now click the demo drop in the menu bar (it shows \(Format.liters(WaterStore.shared.todayTotal))). Waiting up to 60 seconds...")
        for _ in 0..<120 {
            if let popover = NSApp.windows.first(where: {
                $0.isVisible && !Self.isStatusBarWindow($0) && $0 !== settings
                    && $0.frame.width > 200
            }) {
                await pause(1)   // let it finish appearing
                save(popover, as: "popover")
                return quit(nil)
            }
            await pause(0.5)
        }
        quit("No click, so the popover screenshot was skipped.")
    }

    /// Waits (up to 10 s) until the window is in front, so it looks active in the picture.
    private func bringToFront(_ window: NSWindow) async {
        for _ in 0..<20 {
            if NSApp.isActive && window.isKeyWindow { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            await pause(0.5)
        }
        print("Note: \(window.title) never came to the front, so it may look inactive.")
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBar")
    }

    /// Saves the window with its shadow, at full Retina resolution.
    private func save(_ window: NSWindow, as name: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                  CGWindowID(window.windowNumber), [.bestResolution]) else {
            return print("Couldn't capture \(name).")
        }
        let url = outputDir.appendingPathComponent("\(name).png")
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        do {
            try png?.write(to: url)
            print("Saved \(url.path) (\(image.width)×\(image.height))")
        } catch {
            print("Couldn't save \(name): \(error.localizedDescription)")
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func quit(_ problem: String?) {
        if let problem { print(problem) }
        NSApp.terminate(nil)
    }
}
