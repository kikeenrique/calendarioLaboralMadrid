import Foundation
import SchoolCalendar

// Run from the repository root: paths are relative to the working directory.
do {
    let html = try SchoolCalendar.readArchive()
    let events = try SchoolCalendar.validatedEvents(from: html)
    let changed = try SchoolCalendar.writeFeed(SchoolCalendar.buildICS(events: events))

    if changed {
        print("Wrote \(SchoolCalendar.outputPath) with \(events.count) events from \(SchoolCalendar.archivePath).")
    } else {
        print("\(SchoolCalendar.outputPath) is already up to date (\(events.count) events); left untouched.")
    }
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
