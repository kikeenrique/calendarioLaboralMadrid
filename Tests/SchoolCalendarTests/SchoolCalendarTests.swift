import CalendarFeedCore
import Foundation
import Testing

@testable import SchoolCalendar

/// The archived page is the real input the generator runs on, so these tests
/// exercise production behaviour rather than a synthetic fixture.
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SchoolCalendarTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root

private func archivedHTML() throws -> String {
    try String(
        contentsOf: repoRoot.appendingPathComponent(SchoolCalendar.archivePath),
        encoding: .utf8
    )
}

@Suite("Parsing the archived school calendar")
struct ParsingTests {
    @Test("The archive parses to the expected event set")
    func parsesExpectedEvents() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        #expect(events.count == 39)
    }

    @Test("Every category is represented, so no colour silently stops matching")
    func coversEveryCategory() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let counts = Dictionary(grouping: events, by: \.summary).mapValues(\.count)

        #expect(counts["Día festivo o vacacional"] == 20)
        #expect(counts["Otro día no lectivo"] == 6)
        #expect(counts["Repaso y actividades formativas"] == 5)
        #expect(counts["Evaluación final ordinaria"] == 1)
        #expect(counts["Inicio periodo lectivo para los alumnos enseñanzas correspondientes"] == 4)
        #expect(counts["Finalización periodo lectivo para los alumnos enseñanzas correspondientes"] == 3)
    }

    @Test("Weekends are excluded: the source marks every one as non-teaching")
    func excludesWeekends() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let weekends = events.filter { ICS.isWeekend($0.date) }
        #expect(weekends.isEmpty, "found weekend events: \(weekends.map(\.date))")
    }

    @Test("Known dates land in the feed with the right category")
    func knownDates() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let byDate = Dictionary(grouping: events, by: \.date).mapValues { $0.map(\.summary) }

        // Christmas break, per ORDEN 2034/2026: 23 Dec - 6 Jan.
        #expect(byDate["20261223"]?.contains("Día festivo o vacacional") == true)
        #expect(byDate["20270106"]?.contains("Día festivo o vacacional") == true)
        // 26 and 27 December 2026 are a weekend, so they are absent.
        #expect(byDate["20261226"] == nil)
        #expect(byDate["20261227"] == nil)
    }

    @Test("Parsing junk throws rather than emitting an empty feed")
    func emptyInputThrows() {
        #expect(throws: SchoolCalendarError.self) {
            _ = try SchoolCalendar.events(from: "<html><body>no calendar here</body></html>")
        }
    }

    @Test("The sanity floor rejects a page that parses to too few events")
    func sanityFloorRejectsPartialParse() throws {
        // Drop the colour that carries most events, simulating a markup change
        // that silently stops matching one category.
        let damaged = try archivedHTML().replacingOccurrences(of: "#ccff99", with: "#cc0099")

        #expect(throws: SchoolCalendarError.self) {
            _ = try SchoolCalendar.validatedEvents(from: damaged)
        }
        // Without the floor this would have succeeded with a truncated feed.
        let unvalidated = try SchoolCalendar.events(from: damaged)
        #expect(unvalidated.count < SchoolCalendar.minimumExpectedEvents)
    }
}

@Suite("Generating the school ICS")
struct ICSTests {
    @Test("UIDs are stable, unique, and independent of the displayed title")
    func stableUIDs() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let ics = SchoolCalendar.buildICS(events: events)
        let uids = ics.split(separator: "\r\n").filter { $0.hasPrefix("UID:") }

        #expect(uids.count == events.count)
        #expect(Set(uids).count == uids.count, "UIDs must be unique")

        // Rewording a title must not change any UID, or every subscriber's
        // events are torn down and recreated.
        let reworded = events.map {
            SchoolEvent(date: $0.date, kindID: $0.kindID, summary: "Totally different", description: $0.description)
        }
        let rewordedUIDs = SchoolCalendar.buildICS(events: reworded)
            .split(separator: "\r\n").filter { $0.hasPrefix("UID:") }
        #expect(rewordedUIDs == uids)
    }

    @Test("Generation is deterministic for a fixed timestamp")
    func deterministic() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(SchoolCalendar.buildICS(events: events, now: now)
                == SchoolCalendar.buildICS(events: events, now: now))
    }

    @Test("DTEND is always the day after DTSTART, including across DST")
    func dtendNeverCollapses() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let lines = SchoolCalendar.buildICS(events: events).split(separator: "\r\n")

        var starts: [String] = []
        var ends: [String] = []
        for line in lines {
            if line.hasPrefix("DTSTART;VALUE=DATE:") { starts.append(String(line.dropFirst(19))) }
            if line.hasPrefix("DTEND;VALUE=DATE:") { ends.append(String(line.dropFirst(17))) }
        }

        #expect(starts.count == events.count)
        #expect(zip(starts, ends).allSatisfy { $0 != $1 }, "a zero-length all-day event will not render")

        // 2027-03-28 is the European spring-forward day; a system-zone calendar
        // produced DTEND == DTSTART here before the UTC fix.
        if let index = starts.firstIndex(of: "20270328") {
            #expect(ends[index] == "20270329")
        }
    }

    @Test("The feed has valid iCalendar structure with CRLF endings")
    func structure() throws {
        let events = try SchoolCalendar.events(from: try archivedHTML())
        let ics = SchoolCalendar.buildICS(events: events)

        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
        #expect(!ics.contains("\n\n"))

        let begins = ics.components(separatedBy: "BEGIN:VEVENT").count - 1
        let ends = ics.components(separatedBy: "END:VEVENT").count - 1
        #expect(begins == events.count)
        #expect(begins == ends)
    }
}
