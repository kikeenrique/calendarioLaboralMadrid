import CalendarFeedCore
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HolidayFetchError: Error, CustomStringConvertible {
    case invalidURL(String)
    case requestFailed(String)
    case badStatus(Int, String)
    case missingResources
    case noEvents

    public var description: String {
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

public struct Resource: Decodable, Sendable {
    public let url: String?
    public let format: String?
    public let name: String?
    public let description: String?
}

public struct HolidayEvent: Equatable, Sendable {
    public let date: String
    public let summary: String

    public init(date: String, summary: String) {
        self.date = date
        self.summary = summary
    }
}

public enum HolidayCalendar {
    public static let packageID = "300082-0-calendario_laboral"
    public static let packageShowURL =
        "https://datos.madrid.es/api/3/action/package_show?id=\(packageID)"
    public static let keepYearsBack = 1
    public static let outputPath = "docs/madrid-festivos.ics"
    public static let userAgent =
        "MadridCalendarFeeds/1.0 (+https://github.com/kikeenrique/calendarioLaboralMadrid; auto-updating .ics mirror of datos.madrid.es open data)"

    /// Returns whether the feed actually changed; see `ICS.writeIfChanged`.
    @discardableResult
    public static func writeFeed(_ contents: String, to path: String = outputPath) throws -> Bool {
        try ICS.writeIfChanged(contents, to: path)
    }

    // MARK: - Pure parsing

    /// Unfolds RFC 5545 line continuations: a line starting with a space or tab
    /// is a continuation of the previous one.
    public static func unfoldedICSLines(from text: String) -> [String] {
        let rawLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        return rawLines.reduce(into: [String]()) { lines, line in
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(line)
            }
        }
    }

    public static func parseEvents(from icsText: String) -> [HolidayEvent] {
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

    public static func selectICSResources(from resources: [Resource]) throws -> [Resource] {
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

    // MARK: - Fetching

    static func request(for urlString: String) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw HolidayFetchError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func fetchData(from urlString: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: try request(for: urlString))

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw HolidayFetchError.badStatus(httpResponse.statusCode, urlString)
        }

        return data
    }

    static func datasetResources() async throws -> [Resource] {
        let data = try await fetchData(from: packageShowURL)
        let payload = try JSONDecoder().decode(CKANResponse.self, from: data)

        guard payload.success else {
            throw HolidayFetchError.requestFailed("CKAN package_show did not succeed.")
        }

        return payload.result.resources
    }

    public static func fetchAllHolidays() async throws -> [String: String] {
        let icsResources = try selectICSResources(from: try await datasetResources())

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
                FileHandle.standardError.write(
                    Data("  ! skipping \(resource.name ?? "Unknown") (\(urlString)): \(error)\n".utf8)
                )
            }
        }

        print("Fetched resources:")
        fetchedNames.forEach { print("  - \($0)") }

        guard !holidays.isEmpty else {
            throw HolidayFetchError.noEvents
        }

        return holidays
    }

    // MARK: - ICS

    public static func buildICS(from holidays: [String: String], now: Date = Date()) -> String {
        let thisYear = ICS.utcCalendar.component(.year, from: now)
        let minYear = thisYear - keepYearsBack
        let stamp = ICS.timestamp(for: now)

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
            guard let year = Int(date.prefix(4)), year >= minYear else {
                continue
            }
            guard let summary = holidays[date], let end = ICS.dayAfter(date) else {
                continue
            }

            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                "UID:\(date)-madrid-festivo@madrid-holidays-feed",
                "DTSTAMP:\(stamp)",
                "DTSTART;VALUE=DATE:\(date)",
                "DTEND;VALUE=DATE:\(end)",
                "SUMMARY:\(ICS.escaped(summary))",
                "DESCRIPTION:Fuente oficial: datos.madrid.es (Ayuntamiento de Madrid)",
                "TRANSP:TRANSPARENT",
                "END:VEVENT",
            ])
        }

        lines.append("END:VCALENDAR")
        return ICS.joined(lines)
    }
}
