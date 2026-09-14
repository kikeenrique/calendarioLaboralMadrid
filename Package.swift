// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MadridCalendarFeeds",
    platforms: [.macOS(.v13)],
    targets: [
        // Shared iCalendar plumbing: date handling, escaping, stable UIDs.
        .target(name: "CalendarFeedCore"),

        // Pure parsing and ICS generation. No networking, so the tests exercise
        // exactly the code the generator runs.
        .target(name: "SchoolCalendar", dependencies: ["CalendarFeedCore"]),

        // Parsing is pure; the CKAN fetching lives behind it.
        .target(name: "HolidayCalendar", dependencies: ["CalendarFeedCore"]),

        .executableTarget(name: "GenerateSchoolFeed", dependencies: ["SchoolCalendar"]),
        .executableTarget(name: "GenerateHolidayFeed", dependencies: ["HolidayCalendar"]),

        // Local-only: EducaMadrid blocks CI, but a Spanish connection can reach
        // it, so refreshing the archive is a thing you run on your own machine.
        .executableTarget(name: "RefreshSchoolArchive", dependencies: ["SchoolCalendar"]),

        .testTarget(name: "CalendarFeedCoreTests", dependencies: ["CalendarFeedCore"]),
        .testTarget(name: "SchoolCalendarTests", dependencies: ["SchoolCalendar", "CalendarFeedCore"]),
        .testTarget(name: "HolidayCalendarTests", dependencies: ["HolidayCalendar", "CalendarFeedCore"]),
    ]
)
