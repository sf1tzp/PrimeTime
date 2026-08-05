import Foundation

/// A trailing window back from now — the Label Review's scan bound and the
/// History tab's chart range (#163) share these steps, so one picker's worth
/// of cases lives here. (History adds "the displayed week" as a nil case on
/// its optional selection rather than here: a navigable week isn't a trailing
/// window, and the review has no use for it.)
enum TrailingRange: String, CaseIterable, Identifiable {
    case days30, days90, year, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .days30: "Last 30 days"
        case .days90: "Last 90 days"
        case .year: "Last 12 months"
        case .all: "All history"
        }
    }

    /// Lower bound of the window. "All" uses 1970 — traggo needs a concrete
    /// bound, and nothing predates the epoch.
    var start: Date { start(from: Date()) }

    func start(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .days30: return calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        case .days90: return calendar.date(byAdding: .day, value: -90, to: now) ?? .distantPast
        case .year: return calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        case .all: return Date(timeIntervalSince1970: 0)
        }
    }
}
