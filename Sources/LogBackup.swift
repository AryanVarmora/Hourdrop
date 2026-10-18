import Foundation

/// A daily copy of your drink log, in case it's ever damaged or drinks are removed by mistake.
/// The copies sit next to the log in a Backups folder, one per day
/// (water-log-2026-10-18.json), and only the last 14 days are kept.
enum LogBackup {
    static let daysKept = 14

    /// Copies the log into `folder` unless today's copy is already there, then removes the oldest copies.
    static func makeIfNeeded(of log: URL, in folder: URL, now: Date = .now,
                             calendar: Calendar = .current, keep: Int = daysKept) {
        let files = FileManager.default
        guard files.fileExists(atPath: log.path) else { return }   // nothing logged yet
        let copy = folder.appendingPathComponent(fileName(for: now, calendar: calendar))
        guard !files.fileExists(atPath: copy.path) else { return }
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        try? files.copyItem(at: log, to: copy)
        removeOld(in: folder, keep: keep)
    }

    /// e.g. "water-log-2026-10-18.json"
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "water-log-%04d-%02d-%02d.json", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// Deletes all but the newest `keep` daily copies. Any other file in the folder is left alone.
    static func removeOld(in folder: URL, keep: Int) {
        let files = FileManager.default
        let copies = ((try? files.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter(isDailyCopy)
            .sorted()   // the date is in the name, so this is oldest first
        for name in copies.dropLast(keep) {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// True for names like "water-log-2026-10-18.json" and nothing else.
    static func isDailyCopy(_ name: String) -> Bool {
        name.range(of: #"^water-log-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil
    }
}
