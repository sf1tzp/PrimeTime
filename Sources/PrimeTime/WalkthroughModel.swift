import SwiftUI
import PrimeTimeCore
import Observation

/// The dataset behind the interactive walkthrough (issue #93): one
/// hand-authored, deterministic week of demo spans that every step of the tour
/// reads from and mutates. The narrative is continuous — the same spans the
/// user watches aggregate into charts are the ones the schema smells corrupt
/// and heal — so the model is shared across steps rather than per-step
/// fixtures.
///
/// It is deliberately independent of the user's real data and colours: the
/// walkthrough must tell the same story on a fresh install, in demo mode, and
/// on a database full of unrelated tags.
@MainActor
@Observable
final class WalkthroughModel {

    // MARK: The demo week

    /// One span of the demo week. Times are day-offset + hours rather than
    /// absolute dates so the fixture reads like a timetable; `date(day:hour:)`
    /// resolves them against the current week for the daily chart's axis.
    struct DemoSpan: Identifiable, Hashable {
        let id: Int
        /// 0–6 from the start of the displayed week.
        let day: Int
        let startHour: Double
        let hours: Double
        var labels: [SpanLabel]

        var seconds: TimeInterval { hours * 3600 }

        func value(of key: String) -> String? {
            guard let value = labels.first(where: { $0.key == key })?.value,
                  !value.isEmpty else { return nil }
            return value
        }
    }

    /// Midnight starting the week the demo spans land in — the current week,
    /// so the daily chart's axis reads like the user's own History tab.
    let weekStart: Date

    private let calendar = Calendar.current

    init() {
        weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? Calendar.current.startOfDay(for: Date())
    }

    /// The clean four-key week: `repo` / `feat` / `type` / `client`, small
    /// stable vocabularies, one fact per key. Meetings deliberately carry no
    /// `repo` — "decide what untagged means" is part of the story.
    static let baseWeek: [DemoSpan] = [
        DemoSpan(id: 0, day: 0, startHour: 9, hours: 2.5, labels: week("primetime", "onboarding", "feature", "sfi")),
        DemoSpan(id: 1, day: 0, startHour: 11.5, hours: 0.5, labels: [SpanLabel(key: "type", value: "meeting"), SpanLabel(key: "client", value: "sfi")]),
        DemoSpan(id: 2, day: 0, startHour: 13, hours: 3, labels: week("primetime", "charts", "feature", "sfi")),
        DemoSpan(id: 3, day: 1, startHour: 9, hours: 1, labels: [SpanLabel(key: "type", value: "meeting"), SpanLabel(key: "client", value: "acme")]),
        DemoSpan(id: 4, day: 1, startHour: 10, hours: 3, labels: week("acme-app", "billing", "feature", "acme")),
        DemoSpan(id: 5, day: 1, startHour: 14, hours: 2, labels: week("acme-app", "billing", "review", "acme")),
        DemoSpan(id: 6, day: 2, startHour: 9, hours: 3, labels: week("primetime", "onboarding", "feature", "sfi")),
        DemoSpan(id: 7, day: 2, startHour: 13, hours: 2, labels: week("website", "landing", "feature", "sfi")),
        DemoSpan(id: 8, day: 2, startHour: 15, hours: 1, labels: week("primetime", "charts", "review", "sfi")),
        DemoSpan(id: 9, day: 3, startHour: 9, hours: 2, labels: week("acme-app", "billing", "support", "acme")),
        DemoSpan(id: 10, day: 3, startHour: 11, hours: 1, labels: [SpanLabel(key: "type", value: "meeting"), SpanLabel(key: "client", value: "sfi")]),
        DemoSpan(id: 11, day: 3, startHour: 13, hours: 4, labels: week("primetime", "onboarding", "feature", "sfi")),
        DemoSpan(id: 12, day: 4, startHour: 9, hours: 2, labels: week("website", "landing", "review", "sfi")),
        DemoSpan(id: 13, day: 4, startHour: 11, hours: 1, labels: [SpanLabel(key: "type", value: "meeting"), SpanLabel(key: "client", value: "acme")]),
        DemoSpan(id: 14, day: 4, startHour: 13, hours: 2, labels: week("primetime", "charts", "feature", "sfi")),
        DemoSpan(id: 15, day: 4, startHour: 15, hours: 1, labels: [SpanLabel(key: "repo", value: "primetime"), SpanLabel(key: "type", value: "ops"), SpanLabel(key: "client", value: "sfi")]),
        DemoSpan(id: 16, day: 5, startHour: 10, hours: 2, labels: week("website", "landing", "feature", "sfi")),
    ]

    private static func week(_ repo: String, _ feat: String, _ type: String,
                             _ client: String) -> [SpanLabel] {
        [SpanLabel(key: "repo", value: repo),
         SpanLabel(key: "feat", value: feat),
         SpanLabel(key: "type", value: type),
         SpanLabel(key: "client", value: client)]
    }

    // MARK: Schema smells

    /// The four failure modes from the labels guide (primetime.tools/docs/
    /// labels), each a reversible corruption of the demo week. The copy lives
    /// here so every walkthrough presentation tells the identical story.
    enum SchemaSmell: String, CaseIterable, Identifiable {
        case unboundedValues, fusedFacts, driftingKeys, approximateNaming

        var id: String { rawValue }

        var title: String {
            switch self {
            case .unboundedValues: "Unbounded values"
            case .fusedFacts: "Fused facts"
            case .driftingKeys: "Drifting keys"
            case .approximateNaming: "Approximate naming"
            }
        }

        /// What the corrupted charts show, in one sentence.
        var symptom: String {
            switch self {
            case .unboundedValues:
                "Every span invents its own value, so the donut shatters into one-off hairline slices that never add up to a story."
            case .fusedFacts:
                "One label fuses repo, feature, and type into a single value — group by any one of them and there is nothing left to join on."
            case .driftingKeys:
                "Half the week says repo, the other half proj. Each chart only sees its half; history silently splits into two series."
            case .approximateNaming:
                "primetime and PrimeTime are the same project to you, but joins are exact — the charts count them as two."
            }
        }

        /// The way out, phrased like the Help tab's rules.
        var fix: String {
            switch self {
            case .unboundedValues:
                "Keep values from a small, stable vocabulary you would put in a chart legend. Free-form detail belongs in the note."
            case .fusedFacts:
                "One fact per key — repo: primetime, feat: onboarding, type: feature — so every question keeps an axis to group by."
            case .driftingKeys:
                "Pick key names once and stick to them. Label Review can merge a drifted key back into one series."
            case .approximateNaming:
                "Mirror the exact names of systems you join against, letter for letter. Label Review can merge the strays."
            }
        }
    }

    /// The smells currently corrupting the week. Toggling one re-derives
    /// `spans`, so charts re-slice (and heal) in front of the user.
    var activeSmells: Set<SchemaSmell> = []

    /// The tag key the mini charts group by.
    var groupKey = "repo"

    /// The demo week as the active smells leave it.
    var spans: [DemoSpan] { Self.apply(activeSmells, to: Self.baseWeek) }

    /// Applies smells in a fixed order so combinations stay deterministic.
    /// Each transform tolerates labels a previous one already removed.
    static func apply(_ smells: Set<SchemaSmell>, to spans: [DemoSpan]) -> [DemoSpan] {
        var result = spans
        if smells.contains(.fusedFacts) {
            result = result.map { span in
                guard let repo = span.value(of: "repo") else { return span }
                var out = span
                let fused = [repo, span.value(of: "feat"), span.value(of: "type")]
                    .compactMap { $0 }.joined(separator: "-")
                out.labels = span.labels.filter { !["repo", "feat", "type"].contains($0.key) }
                    + [SpanLabel(key: "work", value: fused)]
                return out
            }
        }
        if smells.contains(.driftingKeys) {
            result = result.map { span in
                guard span.day.isMultiple(of: 2) == false else { return span }
                var out = span
                out.labels = span.labels.map {
                    $0.key == "repo" ? SpanLabel(key: "proj", value: $0.value) : $0
                }
                return out
            }
        }
        if smells.contains(.approximateNaming) {
            let nearMisses = ["primetime": "PrimeTime", "acme-app": "acme_app"]
            result = result.map { span in
                // Only some spans drift — that's what makes it split rather
                // than rename.
                guard span.day >= 3 else { return span }
                var out = span
                out.labels = span.labels.map { label in
                    guard label.key == "repo" || label.key == "proj",
                          let miss = nearMisses[label.value] else { return label }
                    return SpanLabel(key: label.key, value: miss)
                }
                return out
            }
        }
        if smells.contains(.unboundedValues) {
            let suffixes = ["fix", "wip", "v2", "polish", "tweak", "final", "cleanup", "new"]
            result = result.map { span in
                var out = span
                out.labels = span.labels.map {
                    $0.key == "feat"
                        ? SpanLabel(key: $0.key, value: "\($0.value)-\(suffixes[span.id % suffixes.count])")
                        : $0
                }
                return out
            }
        }
        return result
    }

    // MARK: Aggregation (mirrors HistoryModel.totals/dailyTotals)

    /// Every key present in the current spans, stable known-schema order
    /// first, then whatever the smells introduced — so a group-by picker can
    /// show `proj` appearing next to `repo` when keys drift.
    var groupableKeys: [String] {
        let known = ["repo", "feat", "type", "client"]
        let present = Set(spans.flatMap { $0.labels.map(\.key) })
        return known.filter(present.contains)
            + present.subtracting(known).sorted()
    }

    /// Week totals per value of `key`, largest first — the donut's data.
    /// Spans without the key are simply absent, exactly as in History.
    func totals(by key: String) -> [SeriesTotal] {
        var acc: [String: TimeInterval] = [:]
        for span in spans {
            guard let value = span.value(of: key) else { continue }
            acc[value, default: 0] += span.seconds
        }
        return acc.map { SeriesTotal(label: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Per-day totals per value of `key` — the stacked daily bar's data.
    func dailyTotals(by key: String) -> [DailyTotal] {
        var acc: [Int: [String: TimeInterval]] = [:]
        for span in spans {
            guard let value = span.value(of: key) else { continue }
            acc[span.day, default: [:]][value, default: 0] += span.seconds
        }
        return acc.flatMap { day, values in
            values.map { DailyTotal(day: date(day: day), label: $0.key, seconds: $0.value) }
        }
        .sorted { $0.day < $1.day }
    }

    var weekTotalSeconds: TimeInterval { spans.reduce(0) { $0 + $1.seconds } }

    /// The whole demo week, for pinning the daily chart's X domain.
    var weekInterval: DateInterval {
        DateInterval(start: weekStart, end: date(day: 7))
    }

    func date(day: Int, hour: Double = 0) -> Date {
        calendar.date(byAdding: .day, value: day, to: weekStart)!
            .addingTimeInterval(hour * 3600)
    }

    // MARK: Colours

    /// Fixed key colours for pills, matching the demo seed's definitions where
    /// they overlap — the walkthrough never reads the user's palette.
    static func keyColor(_ key: String) -> Color {
        let hex: String
        switch key {
        case "repo": hex = "#00897b"
        case "feat": hex = "#8e24aa"
        case "type": hex = "#1e88e5"
        case "client": hex = "#f9a825"
        case "proj": hex = "#d84315"
        case "work": hex = "#e53935"
        default: hex = "#546e7a"
        }
        return Color(hex: hex) ?? .gray
    }

    /// Chart series colours: stable alphabetical assignment over a small
    /// palette, like the History tab. Unbounded values cycle through it, which
    /// is itself part of that smell's story.
    func colorMap(for totals: [SeriesTotal]) -> [String: Color] {
        let palette = ["#00897b", "#8e24aa", "#1e88e5", "#f9a825",
                       "#d84315", "#3949ab", "#43a047", "#6d4c41"]
            .compactMap { Color(hex: $0) }
        let labels = totals.map(\.label).sorted()
        return Dictionary(uniqueKeysWithValues: labels.enumerated().map {
            ($0.element, palette[$0.offset % palette.count])
        })
    }

    // MARK: Step-1 popover mockup

    /// The labels on the mocked running span. Starts mid-thought so the very
    /// first interaction is adding the missing pill.
    var mockupLabels: [SpanLabel] = [
        SpanLabel(key: "repo", value: "primetime"),
        SpanLabel(key: "type", value: "feature"),
    ]

    /// Pills the mockup offers to add. Adding one that shares a key with a
    /// current pill replaces it — same rule as quick labels in the real app.
    static let mockupChoices: [SpanLabel] = [
        SpanLabel(key: "feat", value: "onboarding"),
        SpanLabel(key: "client", value: "sfi"),
        SpanLabel(key: "type", value: "review"),
    ]

    func toggleMockup(_ label: SpanLabel) {
        if mockupLabels.contains(label) {
            mockupLabels.removeAll { $0 == label }
        } else {
            mockupLabels.removeAll { $0.key == label.key }
            mockupLabels.append(label)
        }
    }

    /// The mockup's one-line moral: what the span *is*, given its labels.
    var mockupSummary: String {
        guard !mockupLabels.isEmpty else {
            return "No labels: this span can only ever answer “how long?”."
        }
        let keys = mockupLabels.map(\.key)
        return "This span is nothing but its labels — it will appear in every chart grouped by \(keys.formatted(.list(type: .or)))."
    }
}
