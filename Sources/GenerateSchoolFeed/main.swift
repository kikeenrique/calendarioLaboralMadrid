import Foundation
import SchoolCalendar

// Run from the repository root: paths are relative to the working directory.
do {
    let html = try SchoolCalendar.readArchive()
    let events = try SchoolCalendar.validatedEvents(from: html)
    try SchoolCalendar.writeFeed(SchoolCalendar.buildICS(events: events))
    print("Wrote \(SchoolCalendar.outputPath) with \(events.count) events from \(SchoolCalendar.archivePath).")
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
