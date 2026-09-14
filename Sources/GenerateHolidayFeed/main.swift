import Foundation
import HolidayCalendar

// Run from the repository root: paths are relative to the working directory.
let task = Task {
    do {
        let holidays = try await HolidayCalendar.fetchAllHolidays()
        let ics = HolidayCalendar.buildICS(from: holidays)
        try HolidayCalendar.writeFeed(ics)

        // Count what was actually written, not what was fetched: the retention
        // window drops holidays older than keepYearsBack.
        let written = ics.components(separatedBy: "BEGIN:VEVENT").count - 1
        print("")
        print("Wrote \(HolidayCalendar.outputPath) with \(written) events (\(holidays.count) fetched).")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error)\n".utf8))
        exit(1)
    }
}

_ = task
dispatchMain()
