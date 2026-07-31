import Foundation
import GRDB

// MARK: - Activation

/// Demo mode (#39): the app running against a seeded, throwaway copy of its
/// data, for reproducible screenshots and a functional tour alongside Help.
/// Activated per launch — the choice is never persisted — by either:
///
///     PRIMETIME_DEMO=1 .build/debug/PrimeTime
///     .build/debug/PrimeTime --demo
///
/// Nothing a demo session does can touch real data: timespans, tag sets,
/// definitions and value colours live in `demo.sqlite` beside the real
/// database (rebuilt from scratch on every demo launch, dated relative to
/// now so "the past week" always looks current), and settings reads/writes
/// go to a scratch UserDefaults suite instead of the standard domain.
package enum DemoMode {
    package static var isActive: Bool {
        isActive(environment: ProcessInfo.processInfo.environment,
                 arguments: ProcessInfo.processInfo.arguments)
    }

    /// Split out so tests can probe the parsing without touching the process.
    /// Any non-empty value except "0" activates, so `PRIMETIME_DEMO=true`
    /// also works; the documented spelling is `=1`.
    package static func isActive(environment: [String: String], arguments: [String]) -> Bool {
        if let value = environment["PRIMETIME_DEMO"], !value.isEmpty, value != "0" {
            return true
        }
        return arguments.contains("--demo")
    }
}

// MARK: - Demo store

package extension LocalBackend {
    /// `demo.sqlite`, beside the real database — easy to find (and delete)
    /// but impossible to mistake for it.
    static func demoDatabaseURL() throws -> URL {
        try defaultDatabaseURL().deletingLastPathComponent()
            .appendingPathComponent("demo.sqlite")
    }

    /// Open the demo store, rebuilt from scratch: any previous demo database
    /// is deleted (journal siblings too, so a stale WAL can't resurrect last
    /// launch's rows), migrations run *without* the legacy-UserDefaults
    /// import — the user's real presets must not leak into the demo — and the
    /// seed is written dated relative to `now`.
    static func demo(at url: URL? = nil, now: Date = Date(),
                     calendar: Calendar = .current) throws -> LocalBackend {
        let url = try url ?? demoDatabaseURL()
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        let backend = try LocalBackend(DatabaseQueue(path: url.path),
                                       databaseURL: url, legacyDefaults: nil)
        try DemoSeed.write(to: backend, now: now, calendar: calendar)
        return backend
    }
}

// MARK: - Seed content

/// The demo dataset. Content is designed around the surfaces it has to
/// photograph well: eight tag sets with distinct symbols for the Launcher
/// grid and popover quick start; per-value colours so colour-by-value (on by
/// default) visibly splits pairs like `repo: app` vs `repo: server`; a
/// trailing week of spans with work-day clustering, overlaps, and notes for
/// Log/Calendar/History; two running spans for the live-timer story; two
/// unlabelled ad-hoc spans; and a deliberate `proj` vs `project` key drift
/// for Tag Review to clean up.
///
/// Everything is deterministic given (`now`, `calendar`): past days carry
/// fixed templates chosen by weekday/weekend, today is laid out backwards
/// from `now`.
package enum DemoSeed {

    // MARK: Tag sets (Launcher cards / popover quick start)

    static let tagSets: [TagSet] = [
        TagSet(name: "Deep Work",
               tags: [TagRow(key: "project", value: "primetime"),
                      TagRow(key: "type", value: "programming")],
               symbolName: "brain"),
        // The two app sets carry no `type:` on purpose — they're the surface
        // where the quick labels below add the honing label from scratch
        // (Deep Work shows the replace-same-key story instead).
        TagSet(name: "App Backend",
               tags: [TagRow(key: "repo", value: "website"),
                      TagRow(key: "feat", value: "backend")],
               symbolName: "hammer"),
        TagSet(name: "Server Ops",
               tags: [TagRow(key: "repo", value: "server"),
                      TagRow(key: "type", value: "ops")],
               symbolName: "terminal"),
        TagSet(name: "App Frontend",
               tags: [TagRow(key: "repo", value: "website"),
                      TagRow(key: "feat", value: "frontend")],
               symbolName: "paintbrush"),
        TagSet(name: "Standup",
               tags: [TagRow(key: "team", value: "platform"),
                      TagRow(key: "type", value: "meeting")],
               symbolName: "person.2"),
        TagSet(name: "Email & Admin",
               tags: [TagRow(key: "type", value: "email")],
               symbolName: "envelope"),
        TagSet(name: "Reading",
               tags: [TagRow(key: "topic", value: "swift"),
                      TagRow(key: "type", value: "learning")],
               symbolName: "book"),
        TagSet(name: "Workout",
               tags: [TagRow(key: "type", value: "exercise")],
               symbolName: "figure.run"),
    ]

    // MARK: Quick labels (popover / Launcher hover chips)

    /// Quick labels for the dev-flavoured sets, matched by name because the
    /// set ids are minted fresh on every reseed. The `type:` trio shows both
    /// stories: added from scratch on the app sets (no `type:` baked in) and
    /// replace-same-key on Deep Work. Workout et al. get none — quick labels
    /// are per-set precisely so they don't.
    package static func quickLabels(forSetNamed name: String) -> [TagRow]? {
        switch name {
        case "Deep Work", "App Backend", "App Frontend", "Server Ops":
            return [TagRow(key: "type", value: "programming"),
                    TagRow(key: "type", value: "review"),
                    TagRow(key: "type", value: "debugging")]
        default:
            return nil
        }
    }

    // MARK: Colours
    //
    // Balanced warm/cool on purpose: the brand palette (oranges, reds, dark
    // greys) carries the hero labels — `project:` and its spans dominate the
    // demo, so it goes brand orange — while repo/type/feat keep their cool
    // hues as contrast anchors. Roughly half-and-half across the spectrum.

    static let labelDefinitions: [LabelDefinition] = [
        LabelDefinition(key: "project", color: "#d84315"),
        // Same colour as `project` on purpose: the drifted key should look
        // like what it is — the same concept, misspelled — so the difference
        // shows up in Tag Review, not on every pill.
        LabelDefinition(key: "proj", color: "#d84315"),
        LabelDefinition(key: "repo", color: "#00897b"),
        LabelDefinition(key: "feat", color: "#8e24aa"),
        LabelDefinition(key: "type", color: "#1e88e5"),
        LabelDefinition(key: "team", color: "#795548"),
        LabelDefinition(key: "topic", color: "#f4511e"),
    ]

    /// Per-pair overrides, one hue per value so the colour-by-value story
    /// reads at a glance — `repo: app` blue vs `repo: server` teal, and every
    /// `type:` value its own slice colour in the History donuts.
    static let valueColors: [String: String] = [
        ValueColorKey.join("project", "primetime"): "#e64a19",
        ValueColorKey.join("proj", "primetime"): "#e64a19",   // drift matches too
        ValueColorKey.join("project", "website"): "#ec407a",
        ValueColorKey.join("repo", "website"): "#42a5f5",
        ValueColorKey.join("repo", "server"): "#26a69a",
        ValueColorKey.join("feat", "backend"): "#00acc1",
        ValueColorKey.join("feat", "frontend"): "#f06292",
        ValueColorKey.join("type", "programming"): "#5c6bc0",
        ValueColorKey.join("type", "review"): "#ffa726",
        ValueColorKey.join("type", "meeting"): "#ef5350",
        ValueColorKey.join("type", "email"): "#8d6e63",
        ValueColorKey.join("type", "ops"): "#66bb6a",
        ValueColorKey.join("type", "learning"): "#29b6f6",
        ValueColorKey.join("type", "exercise"): "#9ccc65",
        ValueColorKey.join("type", "support"): "#ffca28",
        ValueColorKey.join("topic", "swift"): "#ff7043",
        ValueColorKey.join("team", "platform"): "#a1887f",
    ]

    // MARK: Spans

    /// One seeded timespan; `end == nil` means running. Internal (and
    /// Hashable) so tests can compare generated seeds directly.
    struct SeedSpan: Hashable {
        let start: Date
        let end: Date?
        let labels: [SpanLabel]
        let note: String
    }

    /// One templated span within a past day, in minutes from that day's
    /// local midnight.
    private struct Draft {
        var startMinute: Int
        var durationMinutes: Int
        var labels: [SpanLabel] = []
        var note: String = ""
    }

    // Label shorthands for the templates.
    private static let standup = [SpanLabel(key: "team", value: "platform"),
                                  SpanLabel(key: "type", value: "meeting")]
    private static let deepWork = [SpanLabel(key: "project", value: "primetime"),
                                   SpanLabel(key: "type", value: "programming")]
    private static let appWork = [SpanLabel(key: "repo", value: "website"),
                                  SpanLabel(key: "type", value: "programming")]
    private static let appReview = [SpanLabel(key: "repo", value: "website"),
                                    SpanLabel(key: "type", value: "review")]
    private static let serverOps = [SpanLabel(key: "repo", value: "server"),
                                    SpanLabel(key: "type", value: "ops")]
    private static let email = [SpanLabel(key: "type", value: "email")]
    private static let exercise = [SpanLabel(key: "type", value: "exercise")]
    private static let reading = [SpanLabel(key: "topic", value: "swift"),
                                  SpanLabel(key: "type", value: "learning")]

    /// Work-day templates, cycled chronologically across the trailing week's
    /// weekdays so no two days chart identically. Any six consecutive days
    /// contain at least four weekdays, so all four variants always appear —
    /// which is what makes the per-variant fixtures (the overlap in B, the
    /// key drift in C, the untagged call in D) launch-date-proof.
    private static let weekdayTemplates: [[Draft]] = [
        // A — a heads-down build day.
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: standup),
            Draft(startMinute: 585, durationMinutes: 105, labels: deepWork,
                  note: "Calendar week grid: overlap columns"),
            Draft(startMinute: 690, durationMinutes: 30, labels: email),
            Draft(startMinute: 780, durationMinutes: 120, labels: appWork,
                  note: "In-place editor for running timers"),
            Draft(startMinute: 900, durationMinutes: 30, labels: appReview,
                  note: "Review: launcher ＋ card"),
            Draft(startMinute: 960, durationMinutes: 60, labels: deepWork),
        ],
        // B — meetings and an upgrade, with a genuine overlap: the incident
        // review ran while the deploy was still being watched (the
        // multi-timer story, visible as shared columns in Calendar).
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: standup),
            Draft(startMinute: 600, durationMinutes: 60, labels: standup,
                  note: "Sprint planning"),
            Draft(startMinute: 660, durationMinutes: 120, labels: serverOps,
                  note: "Postgres 16 upgrade + deploy watch"),
            Draft(startMinute: 735, durationMinutes: 30, labels: standup,
                  note: "Incident review — deploy still rolling"),
            Draft(startMinute: 840, durationMinutes: 120, labels: deepWork,
                  note: "History donuts: per-value colours"),
            Draft(startMinute: 990, durationMinutes: 30, labels: email,
                  note: "Inbox zero attempt"),
        ],
        // C — the drift day: `proj` where every other span says `project`,
        // Tag Review's cleanup fixture.
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: standup),
            Draft(startMinute: 585, durationMinutes: 120,
                  labels: [SpanLabel(key: "proj", value: "primetime"),
                           SpanLabel(key: "type", value: "programming")],
                  note: "Donut hover + selection states"),
            Draft(startMinute: 780, durationMinutes: 60,
                  labels: [SpanLabel(key: "proj", value: "primetime"),
                           SpanLabel(key: "type", value: "review")]),
            Draft(startMinute: 870, durationMinutes: 120, labels: appWork,
                  note: "Log: minute steppers for start/end"),
            Draft(startMinute: 1000, durationMinutes: 20,
                  labels: [SpanLabel(key: "proj", value: "primetime"),
                           SpanLabel(key: "type", value: "email")],
                  note: "Beta tester replies"),
        ],
        // D — a lighter day with an untagged phone call (the ad-hoc story:
        // a blank-timer span left as it was captured).
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: standup),
            Draft(startMinute: 600, durationMinutes: 150, labels: deepWork,
                  note: "Label Review: drag values between keys"),
            Draft(startMinute: 810, durationMinutes: 30,
                  note: "Phone call — forgot the tags"),
            Draft(startMinute: 870, durationMinutes: 60, labels: serverOps),
            Draft(startMinute: 945, durationMinutes: 45,
                  labels: [SpanLabel(key: "project", value: "website"),
                           SpanLabel(key: "type", value: "review")],
                  note: "Landing-page copy pass"),
        ],
    ]

    /// Weekend templates — sparse on purpose, so the History day bars show
    /// the work-day clustering.
    private static let weekendTemplates: [[Draft]] = [
        [
            Draft(startMinute: 600, durationMinutes: 60, labels: exercise,
                  note: "Long run"),
            Draft(startMinute: 900, durationMinutes: 90, labels: reading,
                  note: "Swift concurrency deep-dive"),
        ],
        [
            Draft(startMinute: 630, durationMinutes: 45, labels: exercise),
            Draft(startMinute: 840, durationMinutes: 90,
                  labels: [SpanLabel(key: "project", value: "website"),
                           SpanLabel(key: "type", value: "programming")],
                  note: "Blog draft: shipping a menu-bar app"),
            Draft(startMinute: 990, durationMinutes: 60, labels: reading),
        ],
    ]

    /// Today, laid out backwards from `now` (in minutes) so it always fits
    /// whatever the launch time is; a nil duration is a *running* span. The
    /// last two power the live menu-bar timer and the popover's multi-timer
    /// rows; the support span matches no saved set, so its Log row shows the
    /// save-as-set ＋; the empty entry is the second ad-hoc unlabelled span.
    private static let todayTemplate: [(minutesBeforeNow: Int, durationMinutes: Int?,
                                        labels: [SpanLabel], note: String)] = [
        (220, 75, deepWork, "README screenshot pass"),
        (130, 20, email, ""),
        (105, 15, [], ""),
        (80, 25, [SpanLabel(key: "repo", value: "website"),
                  SpanLabel(key: "type", value: "support")], "Crash report triage"),
        (42, nil, deepWork, "Popover: running-row editor"),
        (9, nil, serverOps, ""),
    ]

    /// The full seed for the trailing week: six templated past days (weekday
    /// variants cycled in chronological order, weekend days sparse) plus
    /// today anchored to `now`.
    static func spans(now: Date, calendar: Calendar = .current) -> [SeedSpan] {
        var result: [SeedSpan] = []
        var weekdayIndex = 0
        var weekendIndex = 0
        for offset in -6...(-1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let template: [Draft]
            if calendar.isDateInWeekend(day) {
                template = weekendTemplates[weekendIndex % weekendTemplates.count]
                weekendIndex += 1
            } else {
                template = weekdayTemplates[weekdayIndex % weekdayTemplates.count]
                weekdayIndex += 1
            }
            for draft in template {
                let start = dayStart.addingTimeInterval(TimeInterval(draft.startMinute * 60))
                result.append(SeedSpan(
                    start: start,
                    end: start.addingTimeInterval(TimeInterval(draft.durationMinutes * 60)),
                    labels: draft.labels, note: draft.note))
            }
        }
        for entry in todayTemplate {
            let start = now.addingTimeInterval(TimeInterval(-entry.minutesBeforeNow * 60))
            let end = entry.durationMinutes.map {
                start.addingTimeInterval(TimeInterval($0 * 60))
            }
            result.append(SeedSpan(start: start, end: end,
                                   labels: entry.labels, note: entry.note))
        }
        return result
    }

    /// Write the whole seed into `backend`, replacing whatever is there —
    /// every surface is replace-all, so re-seeding an existing demo store
    /// yields exactly the same state as a fresh one.
    static func write(to backend: LocalBackend, now: Date = Date(),
                      calendar: Calendar = .current) throws {
        try backend.saveTagSets(tagSets)
        try backend.replaceLabelDefinitions(labelDefinitions)
        try backend.saveValueColors(valueColors)
        try backend.replaceTimeSpans(with: spans(now: now, calendar: calendar))
    }
}
