import Foundation
import Observation

/// What the History (charts) tab groups time by: either every value of one tag
/// key (like the web UI's "Projects" pie for `proj`), or the member tags of a
/// saved tag set (one series per key:value pair in the set).
enum ChartGrouping: Hashable {
    case key(String)
    case tagSet(TagSet.ID)
}

/// One aggregated series slice: a label ("infra", "proj: infra") and a duration.
struct SeriesTotal: Identifiable {
    var id: String { label }
    let label: String
    let seconds: TimeInterval
}

/// One point of the daily chart: seconds spent on `label` during `day`.
struct DailyTotal: Identifiable {
    var id: String { "\(day.timeIntervalSince1970)-\(label)" }
    let day: Date
    let label: String
    let seconds: TimeInterval
}

/// State and behaviour for the history views (Log, Calendar, History/charts).
/// Owns the displayed week, the timespans fetched for it, and aggregation.
/// Sibling of `AppModel`, which owns auth and the live timer.
@MainActor
@Observable
final class HistoryModel {
    @ObservationIgnored unowned let app: AppModel

    /// Midnight at the start of the displayed week (respects the system's
    /// first-day-of-week setting).
    private(set) var weekStart: Date
    /// All timespans overlapping the displayed week — finished ones from the
    /// paged query plus any running timer — newest first.
    private(set) var spans: [TimeSpan] = []
    var isLoading = false
    var errorMessage: String?
    /// The grouping the charts tab renders. Nil until first shown, then
    /// defaulted from the data (see `defaultGrouping`).
    var chartGrouping: ChartGrouping?
    /// Optional second grouping, rendered as a second donut beside the first
    /// for comparing two breakdowns of the same week. Nil = off.
    var chartGrouping2: ChartGrouping?

    /// True once a load has completed, so mutations elsewhere in the app (e.g.
    /// stopping the timer from the popover) know a reload is worthwhile.
    @ObservationIgnored private var hasLoaded = false
    /// Invalidates in-flight loads when the range changes mid-fetch.
    @ObservationIgnored private var loadGeneration = 0

    init(app: AppModel) {
        self.app = app
        weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? Calendar.current.startOfDay(for: Date())
    }

    // MARK: Week navigation

    var weekInterval: DateInterval {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return DateInterval(start: weekStart, end: end)
    }

    /// The seven day-intervals of the displayed week (handles DST-shortened
    /// and -lengthened days by walking real calendar days).
    var days: [DateInterval] {
        var result: [DateInterval] = []
        var cursor = weekStart
        for _ in 0..<7 {
            let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            result.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return result
    }

    var weekLabel: String {
        let last = weekInterval.end.addingTimeInterval(-1)
        let start = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = last.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    var isCurrentWeek: Bool {
        weekInterval.contains(Date())
    }

    func goToPreviousWeek() { shiftWeek(by: -1) }
    func goToNextWeek() { shiftWeek(by: 1) }

    func goToToday() {
        if let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start {
            weekStart = start
            Task { await reload() }
        }
    }

    private func shiftWeek(by weeks: Int) {
        if let start = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: weekStart) {
            weekStart = start
            Task { await reload() }
        }
    }

    // MARK: Loading

    func reload() async {
        guard let backend = app.api, app.isAuthenticated else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let interval = weekInterval
            var finished: [TimeSpan] = []
            var token: PageToken?
            // Page until the backend says there's no more (cap pages defensively).
            for _ in 0..<50 {
                let page = try await backend.timeSpans(from: interval.start,
                                                       to: interval.end,
                                                       page: token)
                finished += page.timeSpans
                guard let next = page.nextPage, !page.timeSpans.isEmpty else { break }
                token = next
            }
            // The paged query excludes running spans; merge those in separately.
            let running = try await backend.timers()
                .filter { $0.start < interval.end }
            guard generation == loadGeneration else { return }  // range changed mid-fetch

            var seen = Set<Int>()
            spans = (running + finished)
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.start > $1.start }
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Reload only if a history view has already fetched data — called after
    /// timer mutations elsewhere in the app so open views stay fresh.
    func reloadIfLoaded() async {
        if hasLoaded { await reload() }
    }

    /// First-load hook for the tab views: fetch once, then leave navigation
    /// and mutations to trigger further loads (so switching tabs is instant).
    func loadIfNeeded() async {
        if !hasLoaded { await reload() }
    }

    // MARK: Editing

    /// Update a timespan in place. Returns true on success (the editor closes).
    func update(id: Int, start: Date, end: Date?, tags: [SpanLabel], note: String) async -> Bool {
        guard let backend = app.api else { return false }
        do {
            try await app.ensureTagDefinitions(for: tags)
            _ = try await backend.updateTimeSpan(id: id, start: start, end: end,
                                                 labels: tags, note: note)
            errorMessage = nil
            await reload()
            await app.refresh()   // the edit may have touched the running timer
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(id: Int) async {
        guard let backend = app.api else { return }
        do {
            try await backend.removeTimeSpan(id: id)
            errorMessage = nil
            await reload()
            await app.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Aggregation

    /// Seconds of `span` that fall inside `interval`. Running spans count up
    /// to now; spans are clipped at the interval edges so overnight entries
    /// contribute to each day they touch.
    func clippedSeconds(of span: TimeSpan, in interval: DateInterval) -> TimeInterval {
        let end = span.end ?? Date()
        let start = max(span.start, interval.start)
        let clippedEnd = min(end, interval.end)
        return max(0, clippedEnd.timeIntervalSince(start))
    }

    /// The series a span contributes to under a grouping, or [] if none.
    /// Grouping by key: the span's value for that key. Grouping by tag set:
    /// one series per member tag the span carries (a span matching several
    /// member tags counts toward each).
    private func seriesLabels(for span: TimeSpan, grouping: ChartGrouping) -> [String] {
        let tags = span.labels
        switch grouping {
        case .key(let key):
            return tags.first(where: { $0.key == key }).map { [$0.value.isEmpty ? "(no value)" : $0.value] } ?? []
        case .tagSet(let id):
            guard let set = app.tagSets.first(where: { $0.id == id }) else { return [] }
            return set.labels
                .filter { tags.contains($0) }
                .map { $0.value.isEmpty ? $0.key : "\($0.key): \($0.value)" }
        }
    }

    /// Week totals per series, largest first.
    func totals(for grouping: ChartGrouping) -> [SeriesTotal] {
        var sums: [String: TimeInterval] = [:]
        let interval = weekInterval
        for span in spans {
            let seconds = clippedSeconds(of: span, in: interval)
            guard seconds > 0 else { continue }
            for label in seriesLabels(for: span, grouping: grouping) {
                sums[label, default: 0] += seconds
            }
        }
        return sums.map { SeriesTotal(label: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Per-day, per-series totals across the week, for the daily chart.
    func dailyTotals(for grouping: ChartGrouping) -> [DailyTotal] {
        var result: [DailyTotal] = []
        for day in days {
            var sums: [String: TimeInterval] = [:]
            for span in spans {
                let seconds = clippedSeconds(of: span, in: day)
                guard seconds > 0 else { continue }
                for label in seriesLabels(for: span, grouping: grouping) {
                    sums[label, default: 0] += seconds
                }
            }
            for (label, seconds) in sums {
                result.append(DailyTotal(day: day.start, label: label, seconds: seconds))
            }
        }
        return result
    }

    /// Total tracked seconds in the week (each span counted once, no grouping).
    var weekTotalSeconds: TimeInterval {
        let interval = weekInterval
        return spans.reduce(0) { $0 + clippedSeconds(of: $1, in: interval) }
    }

    /// Seconds tracked during one day of the week (spans clipped to the day).
    func totalSeconds(in day: DateInterval) -> TimeInterval {
        spans.reduce(0) { $0 + clippedSeconds(of: $1, in: day) }
    }

    /// The most sensible default chart grouping: the tag key used most in the
    /// displayed week, falling back to the first known tag definition.
    func defaultGrouping() -> ChartGrouping? {
        var counts: [String: Int] = [:]
        for span in spans {
            for tag in span.labels { counts[tag.key, default: 0] += 1 }
        }
        if let best = counts.max(by: { $0.value < $1.value })?.key {
            return .key(best)
        }
        if let first = app.tagDefinitions.first?.key {
            return .key(first)
        }
        return nil
    }

    /// Tag keys offered by the grouping picker: every key seen this week plus
    /// every defined key, deduplicated, alphabetical.
    var groupableKeys: [String] {
        var keys = Set(app.tagDefinitions.map(\.key))
        for span in spans {
            for tag in span.labels { keys.insert(tag.key) }
        }
        return keys.sorted()
    }
}

/// "5h 12m", "42m", "38s" — compact duration for totals and log rows.
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    if minutes > 0 { return "\(minutes)m" }
    return "\(total)s"
}
