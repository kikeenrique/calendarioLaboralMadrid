// This generator is deliberately offline. It parses an archived copy of the
// EducaMadrid page and never fetches anything.
//
// WHY WE DO NOT FETCH THE SOURCE
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
// Working around it would mean paying for a Spanish egress (VPS, a scraping API
// with country targeting, or a cloud function in a Spanish region) to re-fetch a
// document that is published once per school year. That is not a trade worth
// making, so we do not try.
//
// The archived copy in resources/ is therefore the source of truth, refreshed by
// hand when a new school year is published. You do not have to watch for that:
// .github/workflows/check-next-school-year.yml does, from a host that is
// reachable, and fails deliberately when a newer calendar appears.
//
// Full probe matrix: .github/workflows/diagnose-educamadrid.yml

import Foundation

enum SchoolCalendarError: Error, CustomStringConvertible {
    case unreadableArchive(String)
    case noEvents

    var description: String {
        switch self {
        case .unreadableArchive(let path):
            return "Could not read the archived school-calendar page at \(path)."
        case .noEvents:
            return "No school-calendar events were found in the archived page."
        }
    }
}

/// `id` is an internal identifier that UIDs are built from; `title` is the text
/// subscribers see. Keeping them separate means the wording can be reworded
/// without changing any UID, so existing events are not torn down and recreated.
struct EventKind {
    let id: String
    let title: String
}

struct SchoolEvent: Comparable {
    let date: String
    let kindID: String
    let summary: String
    let description: String

    init(date: String, kind: EventKind, description: String) {
        self.date = date
        self.kindID = kind.id
        self.summary = kind.title
        self.description = description
    }

    init(date: String, kindID: String, summary: String, description: String) {
        self.date = date
        self.kindID = kindID
        self.summary = summary
        self.description = description
    }

    static func < (lhs: SchoolEvent, rhs: SchoolEvent) -> Bool {
        (lhs.date, lhs.summary, lhs.description) < (rhs.date, rhs.summary, rhs.description)
    }
}

/// Cited in each event's description so subscribers can find the original. Never
/// fetched - see the note at the top of this file.
let sourceURL = "https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27"
/// The source of truth. Refresh by hand when a new school year is published.
let archivePath = "resources/calendario-escolar-26-27.html"
let outputPath = "docs/calendario-escolar-comunidad-madrid.ics"
// The source writes every label in caps and drops the accents that Spanish
// all-caps conventionally omits. Titles here are sentence case with the
// accents restored, which is what reads well in a calendar client.
let periodStartKind = EventKind(
    id: "inicio-periodo-lectivo",
    title: "Inicio periodo lectivo para los alumnos enseñanzas correspondientes"
)
let periodEndKind = EventKind(
    id: "finalizacion-periodo-lectivo",
    title: "Finalización periodo lectivo para los alumnos enseñanzas correspondientes"
)

let colorKinds = [
    "#ccff99": EventKind(id: "festivo-vacacional", title: "Día festivo o vacacional"),
    "#ff9966": EventKind(id: "otro-dia-no-lectivo", title: "Otro día no lectivo"),
    "#cc99ff": EventKind(id: "evaluacion-final-ordinaria", title: "Evaluación final ordinaria"),
    "#ffd5ea": EventKind(id: "repaso-actividades-formativas", title: "Repaso y actividades formativas"),
]

let spanishMonths = [
    "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
    "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
    "septiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
]

func regexMatches(_ pattern: String, in text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
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

func decodeHTMLEntities(_ text: String) -> String {
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

func plainText(from html: String) -> String {
    let withLineBreaks = html.replacingOccurrences(
        of: #"<br\s*/?>"#,
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
    )
    let withoutTags = withLineBreaks.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    return decodeHTMLEntities(withoutTags)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func dateString(day: Int, monthName: String, year: Int) -> String? {
    let month = monthName
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        .lowercased()
    guard let monthNumber = spanishMonths[month] else {
        return nil
    }
    return String(format: "%04d%02d%02d", year, monthNumber, day)
}

/// All dates in this feed are floating all-day values, so every calendar
/// computation has to run in UTC to match `dateFormatter()`. A system-zone
/// calendar would shift day arithmetic across DST transitions.
func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    return calendar
}

/// Deterministic across processes, unlike `Hashable.hashValue`, which Swift
/// seeds per run. UIDs must stay identical between runs or subscribers see
/// every event torn down and recreated.
func stableDigest(_ value: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in Array(value.utf8) {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(hash, radix: 16)
}

func isWeekend(_ date: String) -> Bool {
    guard let parsed = dateFormatter().date(from: date) else {
        return false
    }

    let weekday = utcCalendar().component(.weekday, from: parsed)
    return weekday == 1 || weekday == 7
}

func readArchive() throws -> String {
    guard let html = try? String(contentsOfFile: archivePath, encoding: .utf8) else {
        throw SchoolCalendarError.unreadableArchive(archivePath)
    }
    return html
}

func calendarTableEvents(from html: String) -> [SchoolEvent] {
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
            guard let day = Int(value), let date = dateString(day: day, monthName: monthName, year: year) else {
                continue
            }

            // The source colours every Saturday and Sunday as a non-teaching day.
            // Weekends are already understood to be non-school days, so skip them.
            guard !isWeekend(date) else {
                continue
            }

            events.append(SchoolEvent(date: date, kind: kind, description: "Fuente oficial: \(sourceURL)"))
        }
    }

    return events
}

func listAfter(heading: String, in html: String) -> String? {
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

func periodEvents(heading: String, kind: EventKind, from html: String) -> [SchoolEvent] {
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

func mergedPeriodEvents(_ events: [SchoolEvent]) -> [SchoolEvent] {
    Dictionary(grouping: events, by: { "\($0.date)|\($0.summary)" }).values.map { matchingEvents in
        let first = matchingEvents[0]
        let descriptions = matchingEvents.map(\.description).sorted().joined(separator: "\n")
        return SchoolEvent(
            date: first.date,
            kindID: first.kindID,
            summary: first.summary,
            description: descriptions
        )
    }
}

func sourceEvents(from html: String) throws -> [SchoolEvent] {
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

func dateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd"
    return formatter
}

func timestamp() -> String {
    let formatter = dateFormatter()
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: Date())
}

func escapedICSValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: ";", with: "\\;")
        .replacingOccurrences(of: ",", with: "\\,")
        .replacingOccurrences(of: "\n", with: "\\n")
}

func buildICS(events: [SchoolEvent]) -> String {
    let calendar = utcCalendar()
    let formatter = dateFormatter()
    let stamp = timestamp()
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
        guard let start = formatter.date(from: event.date),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            continue
        }
        lines.append(contentsOf: [
            "BEGIN:VEVENT",
            "UID:\(event.date)-\(stableDigest(event.kindID))-calendario-escolar-comunidad-madrid",
            "DTSTAMP:\(stamp)",
            "DTSTART;VALUE=DATE:\(event.date)",
            "DTEND;VALUE=DATE:\(formatter.string(from: end))",
            "SUMMARY:\(escapedICSValue(event.summary))",
            "DESCRIPTION:\(escapedICSValue(event.description))",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
        ])
    }

    lines.append("END:VCALENDAR")
    return lines.joined(separator: "\r\n") + "\r\n"
}

func writeFeed(_ contents: String) throws {
    try FileManager.default.createDirectory(atPath: "docs", withIntermediateDirectories: true, attributes: nil)
    try contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

do {
    let events = try sourceEvents(from: try readArchive())
    try writeFeed(buildICS(events: events))
    print("Wrote \(outputPath) with \(events.count) events from \(archivePath).")
} catch {
    fputs("ERROR: \(error)\n", stderr)
    exit(1)
}
