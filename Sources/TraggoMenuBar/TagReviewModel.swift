import Foundation
import Observation

/// How far back the tag review scans. Value stats can't come from the server
/// (its tags query only returns key/colour), so the review pages through
/// timespans client-side and the window bounds how much it pulls.
enum ScanRange: String, CaseIterable, Identifiable {
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

    /// Lower bound of the scan. "All" uses 1970 — traggo needs a concrete
    /// bound, and nothing predates the epoch.
    var start: Date {
        let calendar = Calendar.current
        switch self {
        case .days30: return calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        case .days90: return calendar.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        case .year: return calendar.date(byAdding: .year, value: -1, to: Date()) ?? .distantPast
        case .all: return Date(timeIntervalSince1970: 0)
        }
    }
}

/// Usage of one value under a key: how many scanned timespans carry it and
/// how much tracked time they add up to.
struct ValueStat: Identifiable {
    var id: String { value }
    let value: String
    let count: Int
    let seconds: TimeInterval
}

/// One tag key with its value cardinality — the review's unit of display.
struct KeyStat: Identifiable {
    var id: String { key }
    let key: String
    let values: [ValueStat]   // most-used first

    var spanCount: Int { values.reduce(0) { $0 + $1.count } }
    var seconds: TimeInterval { values.reduce(0) { $0 + $1.seconds } }
}

/// State and behaviour for the Tag Review tab: scans timespans to compute
/// per-key value cardinality, and rewrites spans to fix drift (rename a value
/// or a key). Sibling of `HistoryModel`, owned by `AppModel`.
@MainActor
@Observable
final class TagReviewModel {
    @ObservationIgnored unowned let app: AppModel

    var range: ScanRange = .days90
    /// Everything the last scan fetched (finished + running), deduplicated.
    private(set) var spans: [TimeSpan] = []
    private(set) var hasScanned = false
    var isScanning = false
    /// Spans fetched so far, for progress while paging a large window.
    var scannedCount = 0
    var errorMessage: String?

    // Rename progress, observed by the confirm sheet.
    var isRenaming = false
    var renameDone = 0
    var renameTotal = 0
    var renameFailures = 0
    @ObservationIgnored private var cancelRequested = false
    /// Invalidates in-flight scans when the range changes mid-fetch.
    @ObservationIgnored private var scanGeneration = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: Scanning

    func scan() async {
        guard let client = app.api, app.isAuthenticated else { return }
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        scannedCount = 0
        defer { if generation == scanGeneration { isScanning = false } }
        do {
            let from = range.start
            let to = Date().addingTimeInterval(86_400)
            var finished: [TimeSpan] = []
            var cursor: Cursor?
            // Page until done (cap defensively: 500 pages × 100 = 50k spans).
            for _ in 0..<500 {
                let page = try await client.timeSpans(from: from, to: to, cursor: cursor)
                guard generation == scanGeneration else { return }
                finished += page.timeSpans
                scannedCount = finished.count
                guard page.cursor.hasMore, !page.timeSpans.isEmpty else { break }
                cursor = page.cursor
            }
            // The paged query excludes running spans; their tags count too.
            let running = try await client.timers()
            guard generation == scanGeneration else { return }

            var seen = Set<Int>()
            spans = (running + finished).filter { seen.insert($0.id).inserted }
            scannedCount = spans.count
            hasScanned = true
            errorMessage = nil
        } catch {
            guard generation == scanGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Stats

    /// Per-key value cardinality over the scanned spans, messiest keys first
    /// (most distinct values), ties alphabetical.
    var keyStats: [KeyStat] {
        var byKey: [String: [String: (count: Int, seconds: TimeInterval)]] = [:]
        for span in spans {
            let duration = max(0, (span.end?.date ?? Date()).timeIntervalSince(span.start.date))
            for tag in span.tags ?? [] {
                let current = byKey[tag.key]?[tag.value] ?? (0, 0)
                byKey[tag.key, default: [:]][tag.value] =
                    (current.count + 1, current.seconds + duration)
            }
        }
        return byKey.map { key, values in
            KeyStat(key: key,
                    values: values
                        .map { ValueStat(value: $0.key, count: $0.value.count, seconds: $0.value.seconds) }
                        .sorted { ($0.count, $1.value) > ($1.count, $0.value) })
        }
        .sorted { ($0.values.count, $1.key) > ($1.values.count, $0.key) }
    }

    /// Scanned spans carrying `key` (and, when given, exactly `value`) — the
    /// blast radius shown before a rename and the set it rewrites.
    func matches(key: String, value: String? = nil) -> [TimeSpan] {
        spans.filter { span in
            (span.tags ?? []).contains { $0.key == key && (value == nil || $0.value == value) }
        }
    }

    // MARK: Renames

    /// Rewrite every scanned span carrying `key: from` to carry `key: to` —
    /// the typo/merge fix. Also updates local tag sets that reference the old
    /// spelling, or they'd quietly recreate it.
    func renameValue(key: String, from: String, to: String) async {
        await rewrite(matches(key: key, value: from)) { tags in
            tags.map { $0.key == key && $0.value == from ? TimeSpanTag(key: key, value: to) : $0 }
        }
        app.tagSets = app.tagSets.map { set in
            var set = set
            set.tags = set.tags.map { row in
                var row = row
                if normalizeKey(row.key) == key, row.value == from { row.value = to }
                return row
            }
            return set
        }
    }

    /// Rewrite every scanned span carrying key `from` to carry `to` instead,
    /// creating the target definition with the old key's colour if needed.
    /// The old definition stays on the server (traggo keeps it; harmless and
    /// still reusable).
    func renameKey(from: String, to rawTo: String) async {
        let to = normalizeKey(rawTo)
        guard !to.isEmpty, to != from else { return }
        if !app.tagDefinitions.contains(where: { $0.key == to }) {
            let color = app.tagDefinitions.first(where: { $0.key == from })?.color ?? "#2196f3"
            do {
                try await app.api?.createTag(key: to, color: color)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        await rewrite(matches(key: from)) { tags in
            tags.map { $0.key == from ? TimeSpanTag(key: to, value: $0.value) : $0 }
        }
        app.tagSets = app.tagSets.map { set in
            var set = set
            set.tags = set.tags.map { row in
                var row = row
                if normalizeKey(row.key) == from { row.key = to }
                return row
            }
            return set
        }
    }

    func cancelRename() {
        cancelRequested = true
    }

    /// The rewrite engine: N × updateTimeSpan, one span at a time — traggo has
    /// no bulk rename. Not transactional; failures are counted and skipped,
    /// and re-running the same rename converges (already-rewritten spans no
    /// longer match).
    private func rewrite(_ matches: [TimeSpan],
                         _ transform: ([TimeSpanTag]) -> [TimeSpanTag]) async {
        guard let client = app.api, !matches.isEmpty else { return }
        isRenaming = true
        renameDone = 0
        renameTotal = matches.count
        renameFailures = 0
        cancelRequested = false
        defer { isRenaming = false }
        for span in matches {
            if cancelRequested { break }
            do {
                // A nil end leaves running spans running.
                let updated = try await client.updateTimeSpan(
                    id: span.id, start: span.start.date, end: span.end?.date,
                    tags: transform(span.tags ?? []), note: span.note)
                if let index = spans.firstIndex(where: { $0.id == updated.id }) {
                    spans[index] = updated
                }
            } catch {
                renameFailures += 1
                errorMessage = error.localizedDescription
            }
            renameDone += 1
        }
        // The rewrite may have touched the running timer or loaded history.
        await app.refresh()
        await app.history.reloadIfLoaded()
    }
}
