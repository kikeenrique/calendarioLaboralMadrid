import Foundation
import SchoolCalendar

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Local-only tool. EducaMadrid blocks access from outside Spain, so CI cannot
// fetch the page (see Sources/SchoolCalendar/SchoolCalendar.swift). From a
// Spanish connection it is reachable, so refreshing the archive is something you
// run on your own machine:
//
//     swift run RefreshSchoolArchive          # report only
//     swift run RefreshSchoolArchive --write  # update the archive and the feed
//
// It compares the live page against the archive by PARSED EVENTS, not raw bytes:
// Liferay varies about 60 bytes of page chrome between requests, so a byte
// comparison reports a difference on every run.

let shouldWrite = CommandLine.arguments.contains("--write")

func fetchLive() async throws -> String {
    guard let url = URL(string: SchoolCalendar.sourceURL) else {
        throw RefreshError.invalidURL
    }

    var request = URLRequest(url: url, timeoutInterval: 30)
    request.setValue(
        "MadridCalendarFeeds/1.0 (+https://github.com/kikeenrique/calendarioLaboralMadrid)",
        forHTTPHeaderField: "User-Agent"
    )
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue("es-ES,es;q=0.9", forHTTPHeaderField: "Accept-Language")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode else {
        throw RefreshError.noResponse
    }
    guard (200..<300).contains(status) else {
        throw RefreshError.badStatus(status)
    }
    guard let html = String(data: data, encoding: .utf8) else {
        throw RefreshError.notUTF8
    }
    return html
}

enum RefreshError: Error, CustomStringConvertible {
    case invalidURL
    case noResponse
    case notUTF8
    case badStatus(Int)

    var description: String {
        switch self {
        case .invalidURL:
            return "Invalid source URL."
        case .noResponse:
            return "No HTTP response."
        case .notUTF8:
            return "The page could not be decoded as UTF-8."
        case .badStatus(let status):
            return status == 403
                ? """
                    HTTP 403. EducaMadrid blocks access from outside Spain - run this from a \
                    Spanish connection, not a VPN endpoint abroad or a cloud shell.
                    """
                : "HTTP \(status)."
        }
    }
}

func describe(_ events: [SchoolEvent]) -> String {
    let byKind = Dictionary(grouping: events, by: \.summary)
        .map { "\($0.value.count) x \($0.key)" }
        .sorted()
    return byKind.joined(separator: "\n    ")
}

let task = Task {
    do {
        print("Fetching \(SchoolCalendar.sourceURL)")
        let liveHTML = try await fetchLive()
        print("Fetched \(liveHTML.count) characters.\n")

        let liveEvents = try SchoolCalendar.events(from: liveHTML)
        let archivedEvents = try SchoolCalendar.events(from: try SchoolCalendar.readArchive())

        if liveEvents == archivedEvents {
            print("No change: the live page parses to the same \(liveEvents.count) events as the archive.")
            exit(0)
        }

        print("CHANGE DETECTED")
        print("  archive: \(archivedEvents.count) events")
        print("    \(describe(archivedEvents))")
        print("  live:    \(liveEvents.count) events")
        print("    \(describe(liveEvents))")

        let added = liveEvents.filter { !archivedEvents.contains($0) }
        let removed = archivedEvents.filter { !liveEvents.contains($0) }
        if !added.isEmpty {
            print("  added:   \(added.map { "\($0.date) \($0.summary)" }.joined(separator: ", "))")
        }
        if !removed.isEmpty {
            print("  removed: \(removed.map { "\($0.date) \($0.summary)" }.joined(separator: ", "))")
        }

        guard shouldWrite else {
            print("\nRe-run with --write to update \(SchoolCalendar.archivePath) and regenerate the feed.")
            exit(2)
        }

        try liveHTML.write(toFile: SchoolCalendar.archivePath, atomically: true, encoding: .utf8)
        print("\nUpdated \(SchoolCalendar.archivePath).")

        let events = try SchoolCalendar.validatedEvents(from: liveHTML)
        try SchoolCalendar.writeFeed(SchoolCalendar.buildICS(events: events))
        print("Wrote \(SchoolCalendar.outputPath) with \(events.count) events.")
        print("\nReview the diff and commit both files.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
        exit(1)
    }
}

_ = task
dispatchMain()
