import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum SchoolCalendarError: Error, CustomStringConvertible {
    case invalidURL(String)
    case badStatus(Int)
    case unreadablePage
    case noEvents

    var description: String {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .badStatus(let status):
            return "The school calendar source returned HTTP \(status)."
        case .unreadablePage:
            return "The school calendar source could not be decoded as UTF-8."
        case .noEvents:
            return "No school-calendar events were found in the source."
        }
    }
}

struct SchoolEvent: Comparable {
    let date: String
    let summary: String
    let description: String

    static func < (lhs: SchoolEvent, rhs: SchoolEvent) -> Bool {
        (lhs.date, lhs.summary, lhs.description) < (rhs.date, rhs.summary, rhs.description)
    }
}

let sourceURL = "https://www.educa2.madrid.org/web/calendario-escolar-de-la-comunidad-de-madrid/calendario-escolar-26-27"
let outputPath = "docs/calendario-escolar-comunidad-madrid.ics"
let userAgent = "MadridCalendarFeeds/1.0 (+https://github.com/kikeenrique/calendarioLaboralMadrid)"
let periodStartSummary = "INICIO PERIODO LECTIVO PARA LOS ALUMNOS ENSEÑANZAS CORRESPONDIENTES"
let periodEndSummary = "FINALIZACIÓN PERIODO LECTIVO PARA LOS ALUMNOS ENSEÑANZAS CORRESPONDIENTES"

let colorSummaries = [
    "#ccff99": "DIA FESTIVO O VACACIONAL",
    "#ff9966": "OTRO DIA NO LECTIVO",
    "#cc99ff": "EVALUACION FINAL ORDINARIA",
    "#ffd5ea": "REPASO Y ACTIVIDADES FORMATIVAS",
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

func request(for urlString: String) throws -> URLRequest {
    guard let url = URL(string: urlString) else {
        throw SchoolCalendarError.invalidURL(urlString)
    }

    var request = URLRequest(url: url, timeoutInterval: 30)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    return request
}

func fetchSource() async throws -> String {
    let (data, response) = try await URLSession.shared.data(for: request(for: sourceURL))
    if let httpResponse = response as? HTTPURLResponse,
       !(200..<300).contains(httpResponse.statusCode) {
        throw SchoolCalendarError.badStatus(httpResponse.statusCode)
    }
    guard let html = String(data: data, encoding: .utf8) else {
        throw SchoolCalendarError.unreadablePage
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
            guard let summary = colorSummaries.first(where: { attributes.contains($0.key) })?.value else {
                continue
            }

            let value = plainText(from: cell[2])
            guard let day = Int(value), let date = dateString(day: day, monthName: monthName, year: year) else {
                continue
            }

            events.append(SchoolEvent(date: date, summary: summary, description: "Fuente oficial: \(sourceURL)"))
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

func periodEvents(heading: String, summary: String, from html: String) -> [SchoolEvent] {
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
        return SchoolEvent(date: date, summary: summary, description: plainText(from: item))
    }
}

func mergedPeriodEvents(_ events: [SchoolEvent]) -> [SchoolEvent] {
    Dictionary(grouping: events, by: { "\($0.date)|\($0.summary)" }).values.map { matchingEvents in
        let first = matchingEvents[0]
        let descriptions = matchingEvents.map(\.description).sorted().joined(separator: "\n")
        return SchoolEvent(date: first.date, summary: first.summary, description: descriptions)
    }
}

func sourceEvents(from html: String) throws -> [SchoolEvent] {
    let periodBoundaryEvents = mergedPeriodEvents(
        periodEvents(heading: "INICIO", summary: periodStartSummary, from: html)
            + periodEvents(heading: "FINALIZ", summary: periodEndSummary, from: html)
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
            "UID:\(event.date)-\(stableDigest(event.summary))-calendario-escolar-comunidad-madrid",
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

Task {
    do {
        let events = try sourceEvents(from: try await fetchSource())
        try writeFeed(buildICS(events: events))
        print("Wrote \(outputPath) with \(events.count) events.")
        exit(0)
    } catch {
        fputs("ERROR: \(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()
