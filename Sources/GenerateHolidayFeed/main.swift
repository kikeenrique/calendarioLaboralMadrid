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
    try HolidayCalendar.writeFeed(ics)

    // Count what was actually written, not what was fetched: the retention
    // window drops holidays older than keepYearsBack.
    let written = ics.components(separatedBy: "BEGIN:VEVENT").count - 1
    print("")
    print("Wrote \(HolidayCalendar.outputPath) with \(written) events (\(holidays.count) fetched).")
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
    exit(1)
}
