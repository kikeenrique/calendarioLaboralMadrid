import CalendarFeedCore
import Foundation
import Testing

@testable import HolidayCalendar

@Suite("Parsing upstream holiday ICS")
struct HolidayParsingTests {
    @Test("Extracts date and summary from VEVENTs")
    func parsesEvents() {
        let ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            DTSTART;VALUE=DATE:20270101
            SUMMARY:Año Nuevo
            END:VEVENT
            BEGIN:VEVENT
            DTSTART;VALUE=DATE:20270106
            SUMMARY:Epifanía del Señor
            END:VEVENT
            END:VCALENDAR
            """

        let events = HolidayCalendar.parseEvents(from: ics)
        #expect(events == [
            HolidayEvent(date: "20270101", summary: "Año Nuevo"),
            HolidayEvent(date: "20270106", summary: "Epifanía del Señor"),
        ])
    }

    @Test("Unfolds RFC 5545 continuation lines")
    func unfoldsLines() {
        // Unfolding removes the line break AND the single leading whitespace,
        // so a fold may fall mid-word and the halves join with nothing between.
        // The space in "San Isidro Labrador" therefore has to be part of the
        // content, not the fold.
        let ics = """
            BEGIN:VEVENT
            DTSTART;VALUE=DATE:20270515
            SUMMARY:San Isidro Labr
             ador
            END:VEVENT
            """

        #expect(HolidayCalendar.parseEvents(from: ics)
                == [HolidayEvent(date: "20270515", summary: "San Isidro Labrador")])
    }

    @Test("Handles CRLF input as well as LF")
    func handlesCRLF() {
        let ics = "BEGIN:VEVENT\r\nDTSTART;VALUE=DATE:20270501\r\nSUMMARY:Fiesta del Trabajo\r\nEND:VEVENT\r\n"
        #expect(HolidayCalendar.parseEvents(from: ics)
                == [HolidayEvent(date: "20270501", summary: "Fiesta del Trabajo")])
    }

    @Test("Ignores a VEVENT missing a date or summary rather than emitting a partial one")
    func skipsIncompleteEvents() {
        let ics = """
            BEGIN:VEVENT
            SUMMARY:No date here
            END:VEVENT
            BEGIN:VEVENT
            DTSTART;VALUE=DATE:20270101
            END:VEVENT
            """
        #expect(HolidayCalendar.parseEvents(from: ics).isEmpty)
    }

    @Test("Picks only ICS resources that look like holiday feeds")
    func selectsResources() throws {
        let resources = [
            Resource(url: "a", format: "ICS", name: "festivos 2027", description: nil),
            Resource(url: "b", format: "CSV", name: "festivos 2027", description: nil),
            Resource(url: "c", format: "ICS", name: "otra cosa", description: "dias festivos"),
            Resource(url: "d", format: "ICS", name: "unrelated", description: "nothing"),
        ]

        let picked = try HolidayCalendar.selectICSResources(from: resources)
        #expect(picked.map(\.url) == ["a", "c"])
    }

    @Test("Throws when the dataset exposes no usable resource")
    func throwsWithoutResources() {
        #expect(throws: HolidayFetchError.self) {
            _ = try HolidayCalendar.selectICSResources(
                from: [Resource(url: "a", format: "PDF", name: "festivos", description: nil)]
            )
        }
    }
}

@Suite("Generating the holiday ICS")
struct HolidayICSTests {
    private let holidays = [
        "20260815": "Asunción de la Virgen",
        "20270101": "Año Nuevo",
        "20270328": "Domingo de prueba",  // European spring-forward day
    ]

    @Test("DTEND is the day after DTSTART, including across the DST change")
    func dtendAcrossDST() {
        let ics = HolidayCalendar.buildICS(from: holidays, now: Date(timeIntervalSince1970: 1_780_000_000))
        #expect(ics.contains("DTSTART;VALUE=DATE:20270328\r\nDTEND;VALUE=DATE:20270329"))
    }

    @Test("Drops holidays older than the retention window")
    func appliesRetentionWindow() {
        // now = 2026, keepYearsBack = 1, so 2024 must be dropped.
        let now = ICS.dateFormatter.date(from: "20260601")!
        let ics = HolidayCalendar.buildICS(from: ["20240101": "Viejo", "20260101": "Actual"], now: now)

        #expect(!ics.contains("20240101"))
        #expect(ics.contains("20260101"))
    }

    @Test("Events are emitted in date order")
    func sortedByDate() {
        let ics = HolidayCalendar.buildICS(from: holidays, now: Date(timeIntervalSince1970: 1_780_000_000))
        let dates = ics.split(separator: "\r\n")
            .filter { $0.hasPrefix("DTSTART;VALUE=DATE:") }
            .map { String($0.dropFirst(19)) }
        #expect(dates == dates.sorted())
    }

    @Test("Summaries with ICS delimiters are escaped")
    func escapesSummaries() {
        let ics = HolidayCalendar.buildICS(
            from: ["20270101": "Fiesta, con coma; y punto"],
            now: Date(timeIntervalSince1970: 1_780_000_000)
        )
        #expect(ics.contains(#"SUMMARY:Fiesta\, con coma\; y punto"#))
    }

    @Test("Structure is valid with CRLF endings")
    func structure() {
        let ics = HolidayCalendar.buildICS(from: holidays, now: Date(timeIntervalSince1970: 1_780_000_000))
        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(ics.hasSuffix("END:VCALENDAR\r\n"))
        #expect(ics.components(separatedBy: "BEGIN:VEVENT").count - 1
                == ics.components(separatedBy: "END:VEVENT").count - 1)
    }
}
