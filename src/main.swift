import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum HolidayFetchError: Error, CustomStringConvertible {
    case invalidURL(String)
    case requestFailed(String)
    case badStatus(Int, String)
    case missingResources
    case noEvents

    var description: String {
        switch self {
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .requestFailed(let message):
            return message
        case .badStatus(let status, let url):
            return "HTTP \(status) returned for \(url)"
        case .missingResources:
            return "No ICS resources found in the dataset."
        case .noEvents:
            return "Downloaded ICS resources but found zero events."
        }
    }
}

struct CKANResponse: Decodable {
    let success: Bool
    let result: Result

    struct Result: Decodable {
        let resources: [Resource]
    }
}

struct Resource: Decodable {
    let url: String?
    let format: String?
    let name: String?
    let description: String?
}

struct HolidayEvent {
    let date: String
    let summary: String
}

let packageID = "300082-0-calendario_laboral"
let packageShowURL = "https://datos.madrid.es/api/3/action/package_show?id=\(packageID)"
let keepYearsBack = 1
let outputPath = "docs/madrid-festivos.ics"
let userAgent = "MadridFestivosFeedBot/1.0 (+https://github.com/YOUR_GITHUB_USERNAME/madrid-holidays-feed; auto-updating .ics mirror of datos.madrid.es open data)"

func request(for urlString: String) throws -> URLRequest {
    guard let url = URL(string: urlString) else {
        throw HolidayFetchError.invalidURL(urlString)
    }

    var request = URLRequest(url: url, timeoutInterval: 30)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
}

func fetchData(from urlString: String) async throws -> Data {
    let request = try request(for: urlString)
    let (data, response) = try await URLSession.shared.data(for: request)

    if let httpResponse = response as? HTTPURLResponse,
       !(200..<300).contains(httpResponse.statusCode) {
        throw HolidayFetchError.badStatus(httpResponse.statusCode, urlString)
    }

    return data
}

func datasetResources() async throws -> [Resource] {
    let data = try await fetchData(from: packageShowURL)
    let payload = try JSONDecoder().decode(CKANResponse.self, from: data)

    guard payload.success else {
        throw HolidayFetchError.requestFailed("CKAN package_show did not succeed.")
    }

    return payload.result.resources
}

func selectICSResources(from resources: [Resource]) throws -> [Resource] {
    let picked = resources.filter { resource in
        let format = resource.format?.uppercased() ?? ""
        let name = resource.name?.lowercased() ?? ""
        let description = resource.description?.lowercased() ?? ""
        return format == "ICS" && (name.contains("festivos") || description.contains("festivos"))
    }

    guard !picked.isEmpty else {
        throw HolidayFetchError.missingResources
    }

    return picked
}

func unfoldedICSLines(from text: String) -> [String] {
    let rawLines = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")

    return rawLines.reduce(into: [String]()) { lines, line in
        if let first = line.first, (first == " " || first == "\t"), !lines.isEmpty {
            lines[lines.count - 1] += line.dropFirst()
        } else {
            lines.append(line)
        }
    }
}

func parseEvents(from icsText: String) -> [HolidayEvent] {
    var events: [HolidayEvent] = []
    var currentDate: String?
    var currentSummary: String?
    var insideEvent = false

    for line in unfoldedICSLines(from: icsText) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "BEGIN:VEVENT" {
            insideEvent = true
            currentDate = nil
            currentSummary = nil
            continue
        }

        if trimmed == "END:VEVENT" {
            if let date = currentDate, let summary = currentSummary {
                events.append(HolidayEvent(date: date, summary: summary))
            }
            insideEvent = false
            continue
        }

        guard insideEvent, let separator = line.firstIndex(of: ":") else {
            continue
        }

        let key = line[..<separator].split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)

        switch key.uppercased() {
        case "DTSTART":
            if let range = value.range(of: #"\d{8}"#, options: .regularExpression) {
                currentDate = String(value[range])
            }
        case "SUMMARY":
            currentSummary = value
        default:
            break
        }
    }

    return events
}

func fetchAllHolidays() async throws -> [String: String] {
    let resources = try await datasetResources()
    let icsResources = try selectICSResources(from: resources)

    var holidays: [String: String] = [:]
    var fetchedNames: [String] = []

    for resource in icsResources {
        guard let urlString = resource.url else {
            continue
        }

        do {
            let data = try await fetchData(from: urlString)
            let text = String(data: data, encoding: .utf8) ?? ""
            let events = parseEvents(from: text)

            for event in events {
                holidays[event.date] = event.summary
            }

            fetchedNames.append("\(resource.name ?? "Unknown") [\(events.count) events]")
        } catch {
            fputs("  ! skipping \(resource.name ?? "Unknown") (\(urlString)): \(error)\n", stderr)
        }
    }

    print("Fetched resources:")
    fetchedNames.forEach { print("  - \($0)") }

    guard !holidays.isEmpty else {
        throw HolidayFetchError.noEvents
    }

    return holidays
}

func utcTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: Date())
}

func dateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd"
    return formatter
}

func buildCombinedICS(from holidays: [String: String]) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let thisYear = calendar.component(.year, from: Date())
    let minYear = thisYear - keepYearsBack
    let stamp = utcTimestamp()
    let formatter = dateFormatter()

    var lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//madrid-holidays-feed//github-actions//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        "X-WR-CALNAME:Madrid - Dias No Laborables",
        "X-WR-CALDESC:Festivos oficiales de la ciudad de Madrid (nacional + autonomico Comunidad de Madrid + locales). Fuente: datos.madrid.es (Ayuntamiento de Madrid). Generado automaticamente.",
        "X-WR-TIMEZONE:Europe/Madrid",
        "X-PUBLISHED-TTL:P30D",
        "REFRESH-INTERVAL;VALUE=DURATION:P30D",
    ]

    for date in holidays.keys.sorted() {
        guard let year = Int(date.prefix(4)), year >= minYear,
              let startDate = formatter.date(from: date),
              let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            continue
        }

        let end = formatter.string(from: endDate)
        lines.append(contentsOf: [
            "BEGIN:VEVENT",
            "UID:\(date)-madrid-festivo@madrid-holidays-feed",
            "DTSTAMP:\(stamp)",
            "DTSTART;VALUE=DATE:\(date)",
            "DTEND;VALUE=DATE:\(end)",
            "SUMMARY:\(holidays[date] ?? "")",
            "DESCRIPTION:Fuente oficial: datos.madrid.es (Ayuntamiento de Madrid)",
            "TRANSP:TRANSPARENT",
            "END:VEVENT",
        ])
    }

    lines.append("END:VCALENDAR")
    return lines.joined(separator: "\r\n") + "\r\n"
}

func writeFeed(_ contents: String) throws {
    try FileManager.default.createDirectory(
        atPath: "docs",
        withIntermediateDirectories: true,
        attributes: nil
    )
    try contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

Task {
    do {
        let holidays = try await fetchAllHolidays()
        let icsText = buildCombinedICS(from: holidays)
        try writeFeed(icsText)
        print("\nWrote \(outputPath) with \(icsText.components(separatedBy: "BEGIN:VEVENT").count - 1) events.")
        exit(0)
    } catch {
        fputs("ERROR: \(error)\n", stderr)
        exit(1)
    }
}

dispatchMain()
