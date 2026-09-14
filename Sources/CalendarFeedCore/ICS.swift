import Foundation

/// Shared iCalendar plumbing for both feeds.
public enum ICS {
    /// All dates in these feeds are floating all-day values, so every calendar
    /// computation runs in UTC to match `dateFormatter`. A system-zone calendar
    /// shifts day arithmetic across DST transitions: adding one day preserves
    /// local wall-clock time, so at spring forward DTEND lands on DTSTART and
    /// the event collapses to zero length.
    public static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    public static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }

    public static func timestamp(for date: Date = Date()) -> String {
        let formatter = dateFormatter
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// The day after `date` (an ICS all-day DTEND is exclusive).
    public static func dayAfter(_ date: String) -> String? {
        let formatter = dateFormatter
        guard let start = formatter.date(from: date),
              let end = utcCalendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return formatter.string(from: end)
    }

    public static func isWeekend(_ date: String) -> Bool {
        guard let parsed = dateFormatter.date(from: date) else {
            return false
        }
        let weekday = utcCalendar.component(.weekday, from: parsed)
        return weekday == 1 || weekday == 7
    }

    public static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Deterministic across processes, unlike `Hashable.hashValue`, which Swift
    /// seeds per run. UIDs must stay identical between runs, or subscribers see
    /// every event torn down and recreated.
    public static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(value.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// ICS requires CRLF line endings.
    public static func joined(_ lines: [String]) -> String {
        lines.joined(separator: "\r\n") + "\r\n"
    }

    /// The feed with its DTSTAMP lines removed, for comparing two generations
    /// by content alone.
    static func ignoringTimestamps(_ ics: String) -> String {
        ics.components(separatedBy: "\r\n")
            .filter { !$0.hasPrefix("DTSTAMP:") }
            .joined(separator: "\r\n")
    }

    /// Writes only when the calendar content actually differs from what is on
    /// disk, ignoring DTSTAMP. Returns whether anything was written.
    ///
    /// Every run regenerates DTSTAMP, so an unconditional write rewrote every
    /// event line and produced a commit on each scheduled run even when no
    /// holiday had moved. Keeping the old stamp is also the more correct
    /// reading of RFC 5545: DTSTAMP marks when the object was last revised, and
    /// an unchanged calendar has not been revised.
    @discardableResult
    public static func writeIfChanged(_ contents: String, to path: String) throws -> Bool {
        if let existing = try? String(contentsOfFile: path, encoding: .utf8),
           ignoringTimestamps(existing) == ignoringTimestamps(contents) {
            return false
        }
        try write(contents, to: path)
        return true
    }

    public static func write(_ contents: String, to path: String) throws {
        // URL rather than `path as NSString`: String-to-NSString bridging is an
        // Objective-C runtime feature and is not available on Linux, where this
        // runs in CI.
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: nil
        )
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
