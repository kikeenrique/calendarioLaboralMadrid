import Foundation
import Testing

@testable import SchoolCalendar

// The school feed is pinned to one school year, and that year appears in more
// than one file. Only Sources/SchoolCalendar is authoritative, and the
// next-school-year alarm reads only that one - so updating the generator and
// forgetting docs/index.html would leave the site advertising the wrong year
// with nothing to catch it until someone noticed by eye.
//
// These tests make that drift fail on every `swift test`, local and CI, rather
// than at the yearly rollover.
//
// Only files with no legitimate reason to mention another year are checked.
// README.md, resources/README.md, ROADMAP.md and check-next-school-year.yml all
// refer to future years on purpose, so they are deliberately excluded and stay a
// manual step - see resources/README.md.

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SchoolCalendarTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root

private func contents(of relativePath: String) throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
}

/// Every `calendario-escolar-NN-NN` slug in the text, deduplicated.
private func slugYears(in text: String) -> Set<String> {
    let pattern = try! NSRegularExpression(pattern: "calendario-escolar-([0-9]{2}-[0-9]{2})")
    let range = NSRange(text.startIndex..., in: text)
    return Set(pattern.matches(in: text, range: range).compactMap { match in
        Range(match.range(at: 1), in: text).map { String(text[$0]) }
    })
}

/// The year the generator is pinned to, e.g. "26-27".
private var trackedYear: String {
    let years = slugYears(in: SchoolCalendar.archivePath)
    precondition(years.count == 1, "archivePath should carry exactly one school year")
    return years.first!
}

/// "26-27" -> "2026-27", the form shown to readers.
private func longForm(_ year: String) -> String {
    "20" + year
}

@Suite("The pinned school year is consistent across the repository")
struct ConsistencyTests {
    @Test("archivePath and sourceURL agree on the school year")
    func generatorConstantsAgree() {
        #expect(slugYears(in: SchoolCalendar.sourceURL) == [trackedYear])
        #expect(slugYears(in: SchoolCalendar.archivePath) == [trackedYear])
    }

    @Test("The archived page that archivePath points at exists")
    func archiveExists() {
        let path = repoRoot.appendingPathComponent(SchoolCalendar.archivePath).path
        #expect(FileManager.default.fileExists(atPath: path),
                "\(SchoolCalendar.archivePath) is missing; the generator cannot run")
    }

    @Test("The published page advertises the tracked school year")
    func indexPageMatches() throws {
        let html = try contents(of: "docs/index.html")

        #expect(slugYears(in: html) == [trackedYear],
                "docs/index.html links a different school year than the generator tracks")
        #expect(html.contains(longForm(trackedYear)),
                "docs/index.html should show \(longForm(trackedYear)) to readers")
    }

    @Test("The 403 diagnostic probes the tracked school year's page")
    func diagnosticMatches() throws {
        // Slug only: this file also contains dates like 2026-09 in its findings.
        let yaml = try contents(of: ".github/workflows/diagnose-educamadrid.yml")
        #expect(slugYears(in: yaml) == [trackedYear],
                "the diagnostic probes a different page than the generator uses")
    }

    @Test("The alarm can still read the tracked year out of the generator")
    func alarmCanFindTheYear() throws {
        // Mirrors the grep in check-next-school-year.yml. If the constant is
        // renamed or moved, the alarm goes blind; this catches that here.
        let source = try contents(of: "Sources/SchoolCalendar/SchoolCalendar.swift")
        #expect(slugYears(in: source) == [trackedYear])

        let workflow = try contents(of: ".github/workflows/check-next-school-year.yml")
        #expect(workflow.contains("Sources/SchoolCalendar/SchoolCalendar.swift"),
                "the alarm greps a path that no longer exists")
    }
}
