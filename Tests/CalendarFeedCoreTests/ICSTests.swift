import Foundation
import Testing

@testable import CalendarFeedCore

/// Each test gets its own directory so they can run in parallel.
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ics-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

private func feed(stamp: String, summary: String = "Año Nuevo") -> String {
    ICS.joined([
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT",
        "UID:20270101-test",
        "DTSTAMP:\(stamp)",
        "DTSTART;VALUE=DATE:20270101",
        "SUMMARY:\(summary)",
        "END:VEVENT",
        "END:VCALENDAR",
    ])
}

@Suite("Writing a feed only when it changed")
struct WriteIfChangedTests {
    @Test("Creates the file when nothing is there yet")
    func createsMissingFile() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("feed.ics").path

            let wrote = try ICS.writeIfChanged(feed(stamp: "20260101T000000Z"), to: path)
            #expect(wrote)
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test("Creates intermediate directories")
    func createsDirectories() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("docs/nested/feed.ics").path

            let wrote = try ICS.writeIfChanged(feed(stamp: "20260101T000000Z"), to: path)
            #expect(wrote)
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test("A new DTSTAMP alone does not rewrite the file")
    func ignoresTimestampOnlyChange() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("feed.ics").path
            let original = feed(stamp: "20260101T000000Z")
            try ICS.write(original, to: path)

            // Same calendar, regenerated later: only DTSTAMP differs.
            let regenerated = feed(stamp: "20260915T123000Z")
            #expect(regenerated != original)
            let rewrote = try ICS.writeIfChanged(regenerated, to: path)
            #expect(rewrote == false)

            // The file keeps its original stamp, so git sees no change at all.
            let onDisk = try String(contentsOfFile: path, encoding: .utf8)
            #expect(onDisk == original)
        }
    }

    @Test("A real content change is written, carrying the new DTSTAMP")
    func writesRealChange() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("feed.ics").path
            try ICS.write(feed(stamp: "20260101T000000Z"), to: path)

            let changed = feed(stamp: "20260915T123000Z", summary: "Fiesta Nacional")
            let wrote = try ICS.writeIfChanged(changed, to: path)
            #expect(wrote)

            let onDisk = try String(contentsOfFile: path, encoding: .utf8)
            #expect(onDisk == changed)
            #expect(onDisk.contains("DTSTAMP:20260915T123000Z"))
        }
    }

    @Test("Comparison strips only DTSTAMP, not other fields")
    func comparisonIsNarrow() {
        let a = ICS.ignoringTimestamps(feed(stamp: "20260101T000000Z"))
        let b = ICS.ignoringTimestamps(feed(stamp: "20270101T000000Z"))
        #expect(a == b)

        let different = ICS.ignoringTimestamps(feed(stamp: "20260101T000000Z", summary: "Otra cosa"))
        #expect(a != different)
        #expect(a.contains("DTSTART;VALUE=DATE:20270101"))
        #expect(!a.contains("DTSTAMP"))
    }
}

@Suite("Shared ICS helpers")
struct HelperTests {
    @Test("Day arithmetic runs in UTC, so DTEND survives DST transitions")
    func dayAfterAcrossDST() {
        #expect(ICS.dayAfter("20270328") == "20270329")  // European spring forward
        #expect(ICS.dayAfter("20271031") == "20271101")  // autumn back
        #expect(ICS.dayAfter("20271231") == "20280101")  // year boundary
        #expect(ICS.dayAfter("20280228") == "20280229")  // leap year
    }

    @Test("Weekend detection matches the Gregorian calendar")
    func weekends() {
        #expect(ICS.isWeekend("20260905"))   // Saturday
        #expect(ICS.isWeekend("20260906"))   // Sunday
        #expect(!ICS.isWeekend("20260907"))  // Monday
        #expect(!ICS.isWeekend("20260911"))  // Friday
    }

    @Test("Escaping covers the RFC 5545 delimiters")
    func escaping() {
        #expect(ICS.escaped("a,b") == #"a\,b"#)
        #expect(ICS.escaped("a;b") == #"a\;b"#)
        #expect(ICS.escaped("a\nb") == #"a\nb"#)
        #expect(ICS.escaped(#"a\b"#) == #"a\\b"#)
        #expect(ICS.escaped("nothing to do") == "nothing to do")
    }

    @Test("Digests are stable across calls and distinct per input")
    func digests() {
        #expect(ICS.stableDigest("festivo-vacacional") == ICS.stableDigest("festivo-vacacional"))
        #expect(ICS.stableDigest("festivo-vacacional") != ICS.stableDigest("otro-dia-no-lectivo"))
        // Pinned to the value in the published feed: if the digest ever changes,
        // every subscriber's events are torn down and recreated.
        #expect(ICS.stableDigest("festivo-vacacional") == "7ef8e9a78e3ba161")
        #expect(ICS.stableDigest("inicio-periodo-lectivo") == "12766716858f25f0")
    }
}
