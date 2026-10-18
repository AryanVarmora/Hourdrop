import Foundation
import Testing
@testable import HourdropCore

/// Every test here uses its own store with a log in a new temporary folder, never your real one.
@Suite("Saving drinks")
@MainActor
struct WaterStoreTests {
    let folder: URL
    let logFile: URL

    init() throws {
        folder = try makeTempFolder()
        logFile = folder.appendingPathComponent("water-log.json")
    }

    @Test("Logged drinks add up and are saved to the file")
    func addAndSave() {
        let store = WaterStore(fileURL: logFile)
        store.add(ml: 375)
        store.add(ml: 355, drink: .coffee)
        #expect(store.todayTotal == 730)
        #expect(store.total(since: store.dayStart, drink: .water) == 375)
        #expect(store.todayCaffeineMg == 144)

        // A new store reading the same file sees the same drinks.
        let reopened = WaterStore(fileURL: logFile)
        #expect(reopened.todayTotal == 730)
        #expect(reopened.todayEntries.map(\.kind) == [.water, .coffee])
    }

    @Test("Undo last removes only the newest drink, and that's saved too")
    func undo() {
        let store = WaterStore(fileURL: logFile)
        store.add(ml: 375)
        store.add(ml: 166)
        store.undoLast()
        #expect(store.todayTotal == 375)
        #expect(WaterStore(fileURL: logFile).todayTotal == 375)
    }

    @Test("Zero or negative amounts are ignored")
    func ignoresNothing() {
        let store = WaterStore(fileURL: logFile)
        store.add(ml: 0)
        store.add(ml: -100)
        #expect(store.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: logFile.path))
    }

    @Test("Counts and the per-drink split")
    func counts() {
        let store = WaterStore(fileURL: logFile)
        store.add(ml: 355, drink: .coffee)
        store.add(ml: 355, drink: .coffee)
        store.add(ml: 500)
        #expect(store.counts(since: store.dayStart).map(\.count) == [1, 2])   // water, then coffee
        #expect(store.todayByDrink.map(\.ml) == [500, 710])
        #expect(store.lastDrinkAt != nil)
    }

    @Test("Saving keeps a backup of the log from before the day's first change")
    func backupOnSave() throws {
        let store = WaterStore(fileURL: logFile)
        store.add(ml: 375)   // no log file yet, so nothing to back up
        store.add(ml: 166)   // backs up the log with the first drink in it
        store.add(ml: 250)   // today's backup already exists, so it's left as it was

        let backup = folder.appendingPathComponent("Backups")
            .appendingPathComponent(LogBackup.fileName(for: .now))
        let backedUp = try JSONDecoder.forLog.decode([WaterEntry].self, from: Data(contentsOf: backup))
        #expect(backedUp.map(\.ml) == [375])
    }
}

@Suite("Daily backups")
struct LogBackupTests {
    let folder: URL
    let logFile: URL
    let backups: URL
    let today = TestTime.date(2026, 10, 18, 9)

    init() throws {
        folder = try makeTempFolder()
        logFile = folder.appendingPathComponent("water-log.json")
        backups = folder.appendingPathComponent("Backups")
    }

    func backupNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []).sorted()
    }

    @Test("One copy per day, named by date")
    func oncePerDay() throws {
        try Data("[1]".utf8).write(to: logFile)
        LogBackup.makeIfNeeded(of: logFile, in: backups, now: today, calendar: TestTime.calendar)
        #expect(backupNames() == ["water-log-2026-10-18.json"])

        // Later the same day: the morning's copy is kept as it was.
        try Data("[1,2]".utf8).write(to: logFile)
        LogBackup.makeIfNeeded(of: logFile, in: backups, now: today.addingTimeInterval(3600), calendar: TestTime.calendar)
        let copy = backups.appendingPathComponent("water-log-2026-10-18.json")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "[1]")
    }

    @Test("No log yet, no backup")
    func noLog() {
        LogBackup.makeIfNeeded(of: logFile, in: backups, now: today, calendar: TestTime.calendar)
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }

    @Test("Only the last 14 days are kept, and other files are left alone")
    func keepsFourteen() throws {
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        for day in 1...20 {
            let name = LogBackup.fileName(for: TestTime.date(2026, 9, day), calendar: TestTime.calendar)
            try Data("[]".utf8).write(to: backups.appendingPathComponent(name))
        }
        try Data("notes".utf8).write(to: backups.appendingPathComponent("notes.txt"))
        try Data("[]".utf8).write(to: backups.appendingPathComponent("water-log.backup-2026-10-18.json"))

        try Data("[]".utf8).write(to: logFile)
        LogBackup.makeIfNeeded(of: logFile, in: backups, now: today, calendar: TestTime.calendar)

        let names = backupNames()
        #expect(names.filter(LogBackup.isDailyCopy).count == 14)
        #expect(names.contains("water-log-2026-10-18.json"))       // today's, the newest
        #expect(!names.contains("water-log-2026-09-07.json"))      // too old, removed
        #expect(names.contains("water-log-2026-09-08.json"))       // the oldest one kept
        #expect(names.contains("notes.txt"))
        #expect(names.contains("water-log.backup-2026-10-18.json"))
    }

    @Test("Only names like water-log-2026-10-18.json count as daily copies")
    func dailyCopyNames() {
        #expect(LogBackup.isDailyCopy("water-log-2026-10-18.json"))
        #expect(!LogBackup.isDailyCopy("water-log.json"))
        #expect(!LogBackup.isDailyCopy("water-log-2026-10-18.json.bak"))
        #expect(!LogBackup.isDailyCopy("water-log.backup-2026-10-18.json"))
    }
}

extension JSONDecoder {
    /// Reads the log the same way the app writes it.
    static var forLog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
