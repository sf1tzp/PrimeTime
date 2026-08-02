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
    /// stable vocabularies, one fact per key. Two meetings sit on a repo and
    /// feature (a design meeting is still project work) — the fused-facts
    /// smell needs meetings inside the fusion to prove its counter-example.
    /// The other meetings deliberately carry no `repo` — "decide what
    /// untagged means" is part of the story.
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
        DemoSpan(id: 10, day: 3, startHour: 11, hours: 1, labels: week("primetime", "onboarding", "meeting", "sfi")),
        DemoSpan(id: 11, day: 3, startHour: 13, hours: 4, labels: week("primetime", "onboarding", "feature", "sfi")),
        DemoSpan(id: 12, day: 4, startHour: 9, hours: 2, labels: week("website", "landing", "review", "sfi")),
        DemoSpan(id: 13, day: 4, startHour: 11, hours: 1, labels: week("acme-app", "billing", "meeting", "acme")),
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
                "Values become whatever got typed in the moment — keyboard mash that mirrors nothing — so no two spans agree and nothing accumulates."
            case .fusedFacts:
                "One label fuses repo, feature, and type into a single value — group by any one of them and there is nothing left to join on."
            case .driftingKeys:
                "A few recent spans say proj, the rest of the week says repo. Each chart only sees its own key; history silently splits into two series."
            case .approximateNaming:
                "primetime and PrimeTime are the same project to you, but joins are exact — the charts count them as two."
            }
        }

        /// The way out, phrased like the Help tab's rules.
        var fix: String {
            switch self {
            case .unboundedValues:
                "Values should mirror something — a feature, a ticket, a system you join against. feat: issue-12345 is great; if it helps you stay organized across systems, go with it. Mash that mirrors nothing belongs in the note."
            case .fusedFacts:
                "One fact per key — repo: primetime, feat: onboarding, type: feature — so every question keeps an axis to group by."
            case .driftingKeys:
                "Pick key names once and stick to them. Label Review can merge a drifted key back into one series."
            case .approximateNaming:
                "Mirror the exact names of systems you join against, letter for letter. Label Review can merge the strays."
            }
        }

        /// The tag key whose charts show this smell's damage best — the
        /// walkthrough pins its charts to it while the smell is active.
        var demoKey: String {
            switch self {
            case .unboundedValues: "feat"
            case .fusedFacts: "type"
            case .driftingKeys: "repo"
            case .approximateNaming: "repo"
            }
        }

        /// Good/bad example labels shown on the card — the antipattern in
        /// miniature, judged. Only unbounded values needs them: the smell is
        /// about *what a value looks like*, not about structure.
        var examples: [(label: String, good: Bool)] {
            switch self {
            case .unboundedValues:
                // Ticket numbers are the *forge-mirroring* pattern, not the
                // smell (primetime.tools/case-study/joined-to-what-shipped).
                [("feat: onboarding", true),
                 ("feat: issue-12345", true),
                 ("feat: asdklfjasdf", false)]
            default:
                []
            }
        }

        /// The knock-on cost, called out in red beside the corrupted charts.
        var sideEffect: String {
            switch self {
            case .unboundedValues:
                "A colour explosion — the donut scatters into one-off slices too small to mean anything."
            case .fusedFacts:
                "Tidier-looking but incoherent: broad questions like “how much meeting time across all projects?” have nothing left to join on."
            case .driftingKeys:
                "Hours go missing: only the repo half of the week matches — the proj half silently drops out."
            case .approximateNaming:
                "A consistency problem: primetime and PrimeTime count as two, and joins with other systems stop lining up."
            }
        }
    }

    /// The smell currently corrupting the week, if any — radio semantics:
    /// one at a time, so each corruption reads cleanly against the healthy
    /// baseline. Setting it re-derives `spans`, so charts re-slice (and heal)
    /// in front of the user.
    var activeSmell: SchemaSmell?

    /// The tag key the mini charts group by.
    var groupKey = "repo"

    /// The demo week as the active smell leaves it.
    var spans: [DemoSpan] { Self.apply(activeSmell, to: Self.baseWeek) }

    /// One reversible corruption of the week per smell.
    static func apply(_ smell: SchemaSmell?, to spans: [DemoSpan]) -> [DemoSpan] {
        switch smell {
        case nil:
            return spans
        case .fusedFacts:
            return spans.map { span in
                guard let repo = span.value(of: "repo") else { return span }
                var out = span
                let fused = [repo, span.value(of: "feat"), span.value(of: "type")]
                    .compactMap { $0 }.joined(separator: "-")
                out.labels = span.labels.filter { !["repo", "feat", "type"].contains($0.key) }
                    + [SpanLabel(key: "work", value: fused)]
                return out
            }
        case .driftingKeys:
            // Only the website project's late-week spans drift — a couple of
            // hours, an "oof, I missed a bit" rather than half the week gone.
            return spans.map { span in
                guard span.day >= 3, span.value(of: "repo") == "website"
                else { return span }
                var out = span
                out.labels = span.labels.map {
                    $0.key == "repo" ? SpanLabel(key: "proj", value: $0.value) : $0
                }
                return out
            }
        case .approximateNaming:
            let nearMisses = ["primetime": "PrimeTime", "acme-app": "acme_app"]
            return spans.map { span in
                // Only some spans drift — that's what makes it split rather
                // than rename.
                guard span.day >= 3 else { return span }
                var out = span
                out.labels = span.labels.map { label in
                    guard label.key == "repo",
                          let miss = nearMisses[label.value] else { return label }
                    return SpanLabel(key: label.key, value: miss)
                }
                return out
            }
        case .unboundedValues:
            // Not a naming drift — the values are keyboard mash that mirrors
            // nothing, one per span, so nothing repeats. Deliberately no
            // ticket numbers here: issue-12345 mirrors the forge and is an
            // encouraged pattern, not this smell.
            let junk = ["asdklfjasdf", "blah", "stuff", "asdf", "zzz",
                        "final-2", "jjj", "qq", "jkljkl", "tmp", "x2",
                        "wip-wip", "kjhgf", "zxcv", "misc7", "aaa", "test3"]
            return spans.map { span in
                var out = span
                out.labels = span.labels.map {
                    $0.key == "feat"
                        ? SpanLabel(key: $0.key, value: junk[span.id % junk.count])
                        : $0
                }
                return out
            }
        }
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

    /// The pseudo-series that make lost hours *visible*: History would
    /// silently drop them, but the walkthrough shows the gap as greyed-out
    /// missing time so each counter-example lands.
    static let driftedSeriesLabel = "went to proj:"
    static let fusedSeriesLabel = "fused into work:"
    static let missingSeriesLabels: Set<String> = [driftedSeriesLabel,
                                                  fusedSeriesLabel]

    /// The key that swallowed `key`'s spans under the active smell, plus the
    /// grey series label that owns those hours — nil when nothing is hidden.
    private func missingSeries(for key: String) -> (culprit: String, label: String)? {
        switch (activeSmell, key) {
        case (.driftingKeys, "repo"): ("proj", Self.driftedSeriesLabel)
        case (.fusedFacts, "type"): ("work", Self.fusedSeriesLabel)
        default: nil
        }
    }

    /// Hours the active smell moved out of `key`'s reach.
    func missingSeconds(for key: String) -> TimeInterval {
        guard let missing = missingSeries(for: key) else { return 0 }
        return spans.reduce(0) {
            $0 + ($1.value(of: key) == nil && $1.value(of: missing.culprit) != nil
                  ? $1.seconds : 0)
        }
    }

    /// Week totals per value of `key`, largest first — the donut's data.
    /// Spans without the key are simply absent, exactly as in History —
    /// except smell-hidden time, which rides along greyed (see above).
    func totals(by key: String) -> [SeriesTotal] {
        var acc: [String: TimeInterval] = [:]
        for span in spans {
            guard let value = span.value(of: key) else { continue }
            acc[value, default: 0] += span.seconds
        }
        var totals = acc.map { SeriesTotal(label: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
        if let missing = missingSeries(for: key) {
            let seconds = missingSeconds(for: key)
            if seconds > 0 {
                totals.append(SeriesTotal(label: missing.label, seconds: seconds))
            }
        }
        return totals
    }

    /// Per-day totals per value of `key` — the stacked daily bar's data.
    func dailyTotals(by key: String) -> [DailyTotal] {
        var acc: [Int: [String: TimeInterval]] = [:]
        let missing = missingSeries(for: key)
        for span in spans {
            if let value = span.value(of: key) {
                acc[span.day, default: [:]][value, default: 0] += span.seconds
            } else if let missing, span.value(of: missing.culprit) != nil {
                acc[span.day, default: [:]][missing.label, default: 0]
                    += span.seconds
            }
        }
        return acc.flatMap { day, values in
            values.map { DailyTotal(day: date(day: day), label: $0.key, seconds: $0.value) }
        }
        .sorted { $0.day < $1.day }
    }

    /// The fused `work:` labels page 4 shows as proof of the counter-example:
    /// the *meeting* fusions — the spans the user expected the type: meeting
    /// query to return. Two suffice, and the height-constrained detail column
    /// can't fit more plus the explanation.
    var fusedExamples: [SpanLabel] {
        var seen = Set<String>()
        var out: [SpanLabel] = []
        for span in Self.apply(.fusedFacts, to: Self.baseWeek) {
            guard let value = span.value(of: "work"),
                  value.hasSuffix("-meeting"),
                  seen.insert(value).inserted else { continue }
            out.append(SpanLabel(key: "work", value: value))
            if out.count == 2 { break }
        }
        return out
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
        case "book": hex = "#b39ddb"   // pastel purple, distinct from feat's
        default: hex = "#546e7a"
        }
        return Color(hex: hex) ?? .gray
    }

    /// Fixed per-`key: value` colours for every base-week value, modelled on
    /// `DemoSeed.valueColors` (reusing its hexes where the values overlap) —
    /// colouring by pair rather than key is PrimeTime's headline improvement,
    /// so the walkthrough demos it too, still without touching the user's
    /// palette.
    private static let valueColors: [String: String] = [
        ValueColorKey.join("repo", "primetime"): "#e64a19",
        ValueColorKey.join("repo", "website"): "#42a5f5",
        ValueColorKey.join("repo", "acme-app"): "#26a69a",
        ValueColorKey.join("feat", "onboarding"): "#00acc1",
        ValueColorKey.join("feat", "charts"): "#7e57c2",
        ValueColorKey.join("feat", "billing"): "#f06292",
        ValueColorKey.join("feat", "landing"): "#9ccc65",
        ValueColorKey.join("type", "feature"): "#3949ab",
        ValueColorKey.join("type", "review"): "#ffa726",
        // Meetings are overhead, not identity — a muted tinted grey, so they
        // recede next to the work types.
        ValueColorKey.join("type", "meeting"): "#8d6e63",
        ValueColorKey.join("type", "support"): "#ffca28",
        ValueColorKey.join("type", "ops"): "#66bb6a",
        ValueColorKey.join("type", "programming"): "#5c6bc0",
        ValueColorKey.join("type", "planning"): "#ab47bc",
        // SFI in company red — sfi-website's streetfortress wordmark fill
        // (`text only.svg`, = --streetfortress-red); the contract client in
        // a light yellow.
        ValueColorKey.join("client", "sfi"): "#d44141",
        ValueColorKey.join("client", "acme"): "#ffe082",
        // The persona page's example values, pinned so each card's pills
        // read as distinct hues — the hash fallback happily hands
        // neighbours the same colour.
        ValueColorKey.join("repo", "sfi/sfi-website"): "#26a69a",
        ValueColorKey.join("feat", "kb-knowledge-graph"): "#7e57c2",
        ValueColorKey.join("course", "linear-algebra"): "#42a5f5",
        ValueColorKey.join("topic", "eigenvalues"): "#ab47bc",
        ValueColorKey.join("book", "dune"): "#8d6e63",
        ValueColorKey.join("author", "herbert"): "#29b6f6",
        ValueColorKey.join("project", "q3-roadmap"): "#ffa000",
        ValueColorKey.join("meeting", "sprint-planning"): "#e53935",
        ValueColorKey.join("film", "promo-spot"): "#d81b60",
        ValueColorKey.join("stage", "edit"): "#5e35b1",
    ]

    /// The colour for a demo pill or chart series: the fixed pair colour when
    /// the value is known, a deterministic palette pick for smell-generated
    /// values (so unbounded values visibly explode into arbitrary hues), and
    /// the key colour when there is no value to colour by. A drifted `proj`
    /// keeps `repo`'s colours, like the demo seed — the drift loses hours,
    /// not hues.
    static func color(key: String, value: String) -> Color {
        // The missing-time pseudo-series are deliberately hueless.
        guard !missingSeriesLabels.contains(value) else { return .gray.opacity(0.45) }
        guard !value.isEmpty else { return keyColor(key) }
        let lookupKey = key == "proj" ? "repo" : key
        if let hex = valueColors[ValueColorKey.join(lookupKey, value)],
           let fixed = Color(hex: hex) {
            return fixed
        }
        return fallbackPalette[stableHash("\(lookupKey):\(value)") % fallbackPalette.count]
    }

    private static let fallbackPalette = ["#00897b", "#8e24aa", "#1e88e5", "#f9a825",
                                          "#d84315", "#3949ab", "#43a047", "#6d4c41"]
        .compactMap { Color(hex: $0) }

    /// djb2 — `String.hashValue` is seeded per process, and these colours
    /// must survive relaunches.
    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for scalar in string.unicodeScalars {
            hash = (hash &* 33 &+ Int(scalar.value)) & 0x7fffffff
        }
        return hash
    }

    /// Chart series colours for a grouping: the same per-value colours the
    /// pills wear, so a slice is findable in the week list by hue alone.
    func colorMap(for totals: [SeriesTotal], key: String) -> [String: Color] {
        Dictionary(uniqueKeysWithValues: totals.map {
            ($0.label, Self.color(key: key, value: $0.label))
        })
    }

    // MARK: Step-1 popover mockup

    /// The labels on the mocked running span. Starts mid-thought so the very
    /// first interaction is adding the missing pill.
    var mockupLabels: [SpanLabel] = [
        SpanLabel(key: "repo", value: "primetime"),
        SpanLabel(key: "type", value: "feature"),
    ]

    /// The mocked span's note — edited by the mockup's inline editor, like
    /// the real popover's. Free-form detail lives here, not in a label.
    var mockupNote = ""

    func removeMockup(_ label: SpanLabel) {
        mockupLabels.removeAll { $0 == label }
    }

    /// Commit editor drafts: one fact per key — a repeated key keeps the
    /// row typed last, the same rule the real popover applies.
    func commitMockup(labels: [SpanLabel], note: String) {
        var byKey: [String: SpanLabel] = [:]
        var order: [String] = []
        for label in labels {
            if byKey[label.key] == nil { order.append(label.key) }
            byKey[label.key] = label
        }
        mockupLabels = order.compactMap { byKey[$0] }
        mockupNote = note.trimmingCharacters(in: .whitespaces)
    }

    /// The mockup's one-line moral: what the span *is*, given its labels.
    var mockupSummary: String {
        guard !mockupLabels.isEmpty else {
            return "No labels: this span can only ever answer “how long?”."
        }
        let keys = mockupLabels.map(\.key)
        return "With these labels, this timer can be found by \(keys.formatted(.list(type: .or)))."
    }

    // MARK: Created label sets (page 5 → page 6)

    /// A label set created from one of page 5's persona cards. Carries the
    /// real `TagSet.id` (not the name — the user names the set themselves)
    /// so page 6 can offer that persona's quick-label suggestions against
    /// the right set.
    struct CreatedSet: Identifiable, Hashable {
        let setID: UUID
        let personaID: String
        var id: UUID { setID }
    }

    /// The sets created during this walkthrough, in creation order. Lives
    /// here rather than in page state so it survives paging back and forth.
    var createdSets: [CreatedSet] = []
}
