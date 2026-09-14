import CalendarFeedCore
import Foundation

// This module is deliberately offline: it parses an archived copy of the
// EducaMadrid page and never fetches anything.
//
// WHY WE DO NOT FETCH THE SOURCE IN CI
//
// EducaMadrid blocks access from outside Spain, and GitHub's hosted runners are
// not in Spain (ours ran in Phoenix, Arizona). Probed from a runner, every
// request returns a byte-identical stock Apache 403: script UA, browser UA, no
// UA, a full browser header set, HTTP/1.1, a same-site Referer, and cookies
// established on the root path. external.educa2.madrid.org - EducaMadrid's own
// documented host for access from outside Spain - returns 403 too. So does the
// Internet Archive, whose only two captures of the page are the 403 itself, and
// so do public fetch proxies. The rejection is address-based; no client-side
// change reaches it.
//
// From a Spanish connection the page is reachable, so refreshing the archive is
// a local job: see the RefreshSchoolArchive executable.
//
// Full probe matrix: .github/workflows/diagnose-educamadrid.yml

public enum SchoolCalendarError: Error, CustomStringConvertible {
    case unreadableArchive(String)
    case noEvents
    case tooFewEvents(found: Int, minimum: Int)

    public var description: String {
        switch self {
        case .unreadableArchive(let path):
            return "Could not read the archived school-calendar page at \(path)."
        case .noEvents:
            return "No school-calendar events were found in the archived page."
        case .tooFewEvents(let found, let minimum):
            return """
                Only \(found) school-calendar events were found, expected at least \(minimum). \
                The source markup has probably changed and categories are being missed.
                """
        }
    }
}

/// `id` is an internal identifier that UIDs are built from; `title` is the text
/// subscribers see. Keeping them separate means the wording can be reworded
/// without changing any UID, so existing events are not torn down and recreated.
public struct EventKind: Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct SchoolEvent: Comparable, Sendable {
    public let date: String
    public let kindID: String
    public let summary: String
    public let description: String

    public init(date: String, kind: EventKind, description: String) {
        self.date = date
        self.kindID = kind.id
        self.summary = kind.title
        self.description = description
    }

    public init(date: String, kindID: String, summary: String, description: String) {
        self.date = date
        self.kindID = kindID
        self.summary = summary
        self.description = description
    }

    public static func < (lhs: SchoolEvent, rhs: SchoolEvent) -> Bool {
        (lhs.date, lhs.summary, lhs.description) < (rhs.date, rhs.summary, rhs.description)
    }
}

public enum SchoolCalendar {
    /// Cited in each event's description so subscribers can find the original.
    public static let sourceURL =
        "https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27"
    /// The source of truth. Refresh by hand when a new school year is published.
    public static let archivePath = "resources/calendario-escolar-26-27.html"
    public static let outputPath = "docs/calendario-escolar-comunidad-madrid.ics"

    /// A floor, not an exact count: `noEvents` only catches total failure, but a
    /// single changed cell colour would silently drop a whole category while the
    /// run still reported success. The 2026-27 calendar yields 39.
    public static let minimumExpectedEvents = 30

    // The source writes every label in caps and drops the accents that Spanish
    // all-caps conventionally omits. Titles here are sentence case with the
    // accents restored, which is what reads well in a calendar client.
    public static let periodStartKind = EventKind(
        id: "inicio-periodo-lectivo",
        title: "Inicio periodo lectivo para los alumnos enseñanzas correspondientes"
    )
    public static let periodEndKind = EventKind(
        id: "finalizacion-periodo-lectivo",
        title: "Finalización periodo lectivo para los alumnos enseñanzas correspondientes"
    )

    public static let colorKinds = [
        "#ccff99": EventKind(id: "festivo-vacacional", title: "Día festivo o vacacional"),
        "#ff9966": EventKind(id: "otro-dia-no-lectivo", title: "Otro día no lectivo"),
        "#cc99ff": EventKind(id: "evaluacion-final-ordinaria", title: "Evaluación final ordinaria"),
        "#ffd5ea": EventKind(id: "repaso-actividades-formativas", title: "Repaso y actividades formativas"),
    ]

    static let spanishMonths = [
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
        "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
        "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
    ]

    /// Returns whether the feed actually changed; see `ICS.writeIfChanged`.
    @discardableResult
    public static func writeFeed(_ contents: String, to path: String = outputPath) throws -> Bool {
        try ICS.writeIfChanged(contents, to: path)
    }

    public static func readArchive(at path: String = archivePath) throws -> String {
        guard let html = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw SchoolCalendarError.unreadableArchive(path)
        }
        return html
    }

    // MARK: - Parsing

    static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let matchRange = match.range(at: index)
                guard let range = Range(matchRange, in: text) else {
                    return nil
                }
                return String(text[range])
            }
        }
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        let replacements = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'",
            "&aacute;": "á", "&eacute;": "é", "&iacute;": "í", "&oacute;": "ó", "&uacute;": "ú",
            "&Aacute;": "Á", "&Eacute;": "É", "&Iacute;": "Í", "&Oacute;": "Ó", "&Uacute;": "Ú",
            "&ntilde;": "ñ", "&Ntilde;": "Ñ", "&ordm;": "º", "&sup1;": "1",
        ]

        var decoded = text
        for (entity, value) in replacements {
            decoded = decoded.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return decoded
    }

    static func plainText(from html: String) -> String {
        let withLineBreaks = html.replacingOccurrences(
            of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        let withoutTags = withLineBreaks.replacingOccurrences(
            of: #"<[^>]+>"#, with: "", options: .regularExpression
        )
        return decodeHTMLEntities(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func dateString(day: Int, monthName: String, year: Int) -> String? {
        let month = monthName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
        guard let monthNumber = spanishMonths[month] else {
            return nil
        }
        return String(format: "%04d%02d%02d", year, monthNumber, day)
    }

    static func calendarTableEvents(from html: String) -> [SchoolEvent] {
        let monthNames = "ENERO|FEBRERO|MARZO|ABRIL|MAYO|JUNIO|JULIO|AGOSTO|SEPTIEMBRE|OCTUBRE|NOVIEMBRE|DICIEMBRE"
        let tableMatches = regexMatches(#"<table\b[^>]*>(.*?)</table>"#, in: html)
        var events: [SchoolEvent] = []

        for tableMatch in tableMatches {
            guard let table = tableMatch.last,
                  let header = regexMatches("<strong>\\s*(\(monthNames))\\s+(\\d{4})\\s*</strong>", in: table).first,
                  header.count == 3,
                  let year = Int(header[2]) else {
                continue
            }

            let monthName = header[1].lowercased()
            for cell in regexMatches(#"<td\b([^>]*)>(.*?)</td>"#, in: table) where cell.count == 3 {
                let attributes = cell[1].lowercased()
                guard let kind = colorKinds.first(where: { attributes.contains($0.key) })?.value else {
                    continue
                }

                let value = plainText(from: cell[2])
                guard let day = Int(value),
                      let date = dateString(day: day, monthName: monthName, year: year) else {
                    continue
                }

                // The source colours every Saturday and Sunday as a non-teaching
                // day. Weekends are already understood to be non-school days.
                guard !ICS.isWeekend(date) else {
                    continue
                }

                events.append(SchoolEvent(date: date, kind: kind, description: "Fuente oficial: \(sourceURL)"))
            }
        }

        return events
    }

    static func listAfter(heading: String, in html: String) -> String? {
        guard let headingRange = html.range(of: heading, options: [.caseInsensitive]) else {
            return nil
        }
        let remainder = html[headingRange.lowerBound...]
        guard let listStart = remainder.range(of: "<ul", options: [.caseInsensitive]),
              let listEnd = remainder[listStart.lowerBound...].range(of: "</ul>", options: [.caseInsensitive]) else {
            return nil
        }
        return String(remainder[listStart.lowerBound..<listEnd.upperBound])
    }

    static func periodEvents(heading: String, kind: EventKind, from html: String) -> [SchoolEvent] {
        guard let list = listAfter(heading: heading, in: html) else {
            return []
        }

        let datePattern = #"\[(\d{1,2})\s+de\s+([[:alpha:]áéíóúñ]+)\s+(?:de\s+)?(\d{4})\]"#
        return regexMatches(#"<li[^>]*>(.*?)</li>"#, in: list).compactMap { match in
            guard let item = match.last,
                  let dateMatch = regexMatches(datePattern, in: plainText(from: item)).first,
                  dateMatch.count == 4,
                  let day = Int(dateMatch[1]),
                  let year = Int(dateMatch[3]),
                  let date = dateString(day: day, monthName: dateMatch[2], year: year) else {
                return nil
            }
            return SchoolEvent(date: date, kind: kind, description: plainText(from: item))
        }
    }

    static func mergedPeriodEvents(_ events: [SchoolEvent]) -> [SchoolEvent] {
        Dictionary(grouping: events, by: { "\($0.date)|\($0.summary)" }).values.map { matchingEvents in
            let first = matchingEvents[0]
            let descriptions = matchingEvents.map(\.description).sorted().joined(separator: "\n")
            return SchoolEvent(
                date: first.date, kindID: first.kindID, summary: first.summary, description: descriptions
            )
        }
    }

    /// Parses without the sanity floor, so callers that only want to compare two
    /// versions of the page are not blocked by it.
    public static func events(from html: String) throws -> [SchoolEvent] {
        let periodBoundaryEvents = mergedPeriodEvents(
            periodEvents(heading: "INICIO", kind: periodStartKind, from: html)
                + periodEvents(heading: "FINALIZ", kind: periodEndKind, from: html)
        )
        let events = calendarTableEvents(from: html) + periodBoundaryEvents

        let uniqueEvents = Dictionary(grouping: events, by: { "\($0.date)|\($0.summary)|\($0.description)" })
            .compactMap { $0.value.first }
            .sorted()

        guard !uniqueEvents.isEmpty else {
            throw SchoolCalendarError.noEvents
        }
        return uniqueEvents
    }

    /// Parses and asserts the sanity floor. This is what the generator uses.
    public static func validatedEvents(from html: String) throws -> [SchoolEvent] {
        let events = try events(from: html)
        guard events.count >= minimumExpectedEvents else {
            throw SchoolCalendarError.tooFewEvents(found: events.count, minimum: minimumExpectedEvents)
        }
        return events
    }

    // MARK: - ICS

    public static func buildICS(events: [SchoolEvent], now: Date = Date()) -> String {
        let stamp = ICS.timestamp(for: now)
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//calendario-escolar-comunidad-madrid//github-actions//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:Calendario Escolar Comunidad de Madrid",
            "X-WR-CALDESC:Calendario escolar oficial de la Comunidad de Madrid. Generado automaticamente desde EducaMadrid.",
            "X-WR-TIMEZONE:Europe/Madrid",
        ]

        for event in events {
            guard let end = ICS.dayAfter(event.date) else {
                continue
            }
            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                "UID:\(event.date)-\(ICS.stableDigest(event.kindID))-calendario-escolar-comunidad-madrid",
                "DTSTAMP:\(stamp)",
                "DTSTART;VALUE=DATE:\(event.date)",
                "DTEND;VALUE=DATE:\(end)",
                "SUMMARY:\(ICS.escaped(event.summary))",
                "DESCRIPTION:\(ICS.escaped(event.description))",
                "TRANSP:TRANSPARENT",
                "END:VEVENT",
            ])
        }

        lines.append("END:VCALENDAR")
        return ICS.joined(lines)
    }
}
