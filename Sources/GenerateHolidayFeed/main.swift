import Foundation
import HolidayCalendar

// Top-level `await` rather than Task + dispatchMain(): dispatchMain relies on
// Foundation re-exporting Dispatch, which is Apple-platform behaviour. This runs
// on Linux in CI.
//
// Run from the repository root: paths are relative to the working directory.
do {
    let holidays = try await HolidayCalendar.fetchAllHolidays()
    let ics = HolidayCalendar.buildICS(from: holidays)
    let changed = try HolidayCalendar.writeFeed(ics)

    // Count what is in the feed, not what was fetched: the retention window
    // drops holidays older than keepYearsBack.
    let count = ics.components(separatedBy: "BEGIN:VEVENT").count - 1
    print("")
    if changed {
        print("Wrote \(HolidayCalendar.outputPath) with \(count) events (\(holidays.count) fetched).")
    } else {
        print("\(HolidayCalendar.outputPath) is already up to date (\(count) events); left untouched.")
    }
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
