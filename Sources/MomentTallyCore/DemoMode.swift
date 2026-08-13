import Foundation
import GRDB

// MARK: - Activation

/// Demo mode (#39): the app running against a seeded, throwaway copy of its
/// data, for reproducible screenshots and a functional tour alongside Help.
/// Activated per launch — the choice is never persisted — by either:
///
///     MOMENTTALLY_DEMO=1 .build/debug/MomentTally
///     .build/debug/MomentTally --demo
///
/// Nothing a demo session does can touch real data: timespans, tag sets,
/// definitions and value colours live in `demo.sqlite` beside the real
/// database (rebuilt from scratch on every demo launch, dated relative to
/// now so "the past month" always looks current), and settings reads/writes
/// go to a scratch UserDefaults suite instead of the standard domain.
package enum DemoMode {
    package static var isActive: Bool {
        isActive(environment: ProcessInfo.processInfo.environment,
                 arguments: ProcessInfo.processInfo.arguments)
    }

    /// Split out so tests can probe the parsing without touching the process.
    /// Any non-empty value except "0" activates, so `MOMENTTALLY_DEMO=true`
    /// also works; the documented spelling is `=1`.
    package static func isActive(environment: [String: String], arguments: [String]) -> Bool {
        if let value = environment["MOMENTTALLY_DEMO"], !value.isEmpty, value != "0" {
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

/// The demo dataset, renovated for the onboarding "Pro-Moves" examples
/// (#172). Content is designed around the surfaces it has to photograph
/// well, and the persona is a contractor whose scheme shows all three
/// recommended patterns:
///
/// - **Quick-labels-only sets** (Gaming, Workout, Reading): no preset
///   labels, one chip per game/activity/book — easy to add or remove
///   without touching history.
/// - **Value-less labels** (Frontend/Backend Work's `feature:`, the client
///   sets' `repo:`/`issue:`): quick-starting one opens the popover editor
///   with the empty value focused, ready for a pasted issue number (#149,
///   #162).
/// - **Multi-client, multi-project sets** (Moment Tally, Meridian, Lighthouse,
///   Velocity Consulting): `client:` + `project:` presets with `type:` and
///   `meeting:` quick labels, so History's combined view has real
///   type × project, type × client and meeting × client axes to group by.
///
/// Spans cover a trailing month — enough for the History range selector's
/// "Last 30 days" — with work-day clustering, overlaps, notes, evening and
/// weekend leisure spans, two running spans, unlabelled ad-hoc spans, and a
/// deliberate `proj:` vs `repo:` key drift for Label Review to move
/// (`proj: company-website` → `repo: company-website`).
///
/// Everything is deterministic given (`now`, `calendar`): past days carry
/// fixed templates chosen by weekday/weekend, today is laid out backwards
/// from `now`.
package enum DemoSeed {

    // MARK: Tag sets (Launcher cards / popover quick start)

    static let tagSets: [TagSet] = [
        // The "common work" pair: a shared value-less `feature:` links time
        // across both repos, and quick-starting either opens the editor with
        // the empty value focused (#149/#162).
        // TagSet(name: "Frontend Work",
        //        tags: [TagRow(key: "repo", value: "company-website"),
        //               TagRow(key: "feature", value: "")],
        //        symbolName: "paintbrush"),
        // TagSet(name: "Backend Work",
        //        tags: [TagRow(key: "repo", value: "infrastructure"),
        //               TagRow(key: "feature", value: "")],
        //        symbolName: "terminal"),
        // The multi-client pattern: `project:` + `client:` presets, with
        // value-less `repo:`/`issue:` to fill in per start. Their quick
        // labels below carry the `type:`/`meeting:` axes History's combined
        // view groups by. `project:` leads so each launcher card borrows its
        // *project's* colour — client-first would paint Moment Tally and
        // Meridian the same sfi blue.
        TagSet(name: "Moment Tally App",
               tags: [TagRow(key: "project", value: "moment-tally"),
                      TagRow(key: "client", value: "sfi"),
                      TagRow(key: "issue", value: "")],
               symbolName: "laptopcomputer"),
        TagSet(name: "Meridian Website",
               tags: [TagRow(key: "project", value: "meridian"),
                      TagRow(key: "client", value: "acme-inc"),
                      ],
               symbolName: "globe"),
        // TagSet(name: "Lighthouse",
        //        tags: [TagRow(key: "project", value: "lighthouse"),
        //               TagRow(key: "client", value: "code-corps"),
        //               TagRow(key: "repo", value: ""),
        //               TagRow(key: "issue", value: "")],
        //        symbolName: "light.beacon.max"),
        // Meetings-only engagement: no repo/issue to fill in, just the
        // `meeting:` chips.
        // TagSet(name: "Velocity Consulting",
        //        tags: [TagRow(key: "project", value: "velocity-consulting"),
        //               TagRow(key: "client", value: "code-corps")],
        //        symbolName: "briefcase"),
        // Quick-labels-only sets: no presets, so the card colour comes from
        // `colorHex` (matched to the key's definition colour below).
        TagSet(name: "Gaming", symbolName: "gamecontroller", colorHex: "#752fe6ff"),
        TagSet(name: "Workout", symbolName: "figure.run", colorHex: "#7ce751ff"),
        TagSet(name: "Reading", symbolName: "book", colorHex: "#26a69a"),
    ]

    // MARK: Quick labels (popover / Launcher hover chips)

    /// Quick labels for every set, matched by name because the set ids are
    /// minted fresh on every reseed. The work sets carry the `type:` trio
    /// (added from scratch — no `type:` is baked into any set); the client
    /// sets add `meeting:` chips so one hover covers coding and ceremonies;
    /// the leisure sets are chips *only* — the whole set is its quick
    /// labels.
    package static func quickLabels(forSetNamed name: String) -> [TagRow]? {
        let type = [TagRow(key: "type", value: "planning"),
                    TagRow(key: "type", value: "review"),
                    TagRow(key: "type", value: "debugging")]
        switch name {
        case "Moment Tally App", "Backend Work":
            return type
        case "Meridian Website", "Lighthouse":
            return type + [TagRow(key: "meeting", value: "retrospective"),
                           TagRow(key: "meeting", value: "standup"),
                           TagRow(key: "meeting", value: "handoff")]
        case "Velocity Consulting":
            return [TagRow(key: "meeting", value: "retrospective"),
                    TagRow(key: "meeting", value: "standup"),
                    TagRow(key: "meeting", value: "release-planning")]
        case "Gaming":
            return [TagRow(key: "game", value: "baldurs-gate"),
                    TagRow(key: "game", value: "no-mans-sky"),
                    TagRow(key: "game", value: "cyberpunk")]
        case "Workout":
            return [TagRow(key: "activity", value: "bike"),
                    TagRow(key: "activity", value: "run"),
                    TagRow(key: "activity", value: "gym")]
        case "Reading":
            return [TagRow(key: "book", value: "the-director"),
                    TagRow(key: "book", value: "crux"),
                    TagRow(key: "book", value: "the-wayfinder")]
        default:
            return nil
        }
    }

    // MARK: Colours
    //
    // The persona palette (#201) — the website's launcher.ts hexes, one per
    // persona tile, spread across the demo's keys and values so every
    // surface photographs in the same spectrum the momenttally.com persona
    // ring uses. The hero label — `project: moment-tally` and its spans
    // dominate the demo — carries the Programming persona's apricot; the
    // rest balance warm/cool as contrast anchors instead of the old
    // orange/red PrimeTime lean. `client: sfi` keeps streetfortress red
    // deliberately (the company mark, not a palette pick).

    static let labelDefinitions: [LabelDefinition] = [
        LabelDefinition(key: "client", color: "#5856d6"),   // Freelance
        LabelDefinition(key: "project", color: "#f7b060"),  // Programming
        LabelDefinition(key: "repo", color: "#007aff"),     // Side Project
        // Same colour as `repo` on purpose: the drifted key should look
        // like what it is — the same concept, misspelled — so the difference
        // shows up in Label Review, not on every pill.
        LabelDefinition(key: "proj", color: "#007aff"),
        LabelDefinition(key: "feature", color: "#ec407a"),  // Volunteering
        LabelDefinition(key: "issue", color: "#66bb6a"),    // Gardening
        LabelDefinition(key: "type", color: "#30b0c7"),     // Language
        LabelDefinition(key: "meeting", color: "#af52de"),  // Music Practice
        LabelDefinition(key: "game", color: "#6015d8ff"),     // Streaming
        LabelDefinition(key: "activity", color: "#7fd84bff"), // Fitness
        LabelDefinition(key: "book", color: "#26a69a"),     // Leisure
    ]

    /// Per-pair overrides, one hue per value so the colour-by-value story
    /// reads at a glance — every `type:`/`meeting:` value its own slice in
    /// the History donuts, and the combined view's type × client and
    /// meeting × client pairings stay tellable-apart.
    static let valueColors: [String: String] = [
        ValueColorKey.join("project", "moment-tally"): "#58d8adff",   // Programming
        ValueColorKey.join("project", "meridian"): "#f09e52ff",       // Language
        ValueColorKey.join("project", "lighthouse"): "#ffe600ff",     // Cooking
        ValueColorKey.join("project", "velocity-consulting"): "#66bb6a",
        ValueColorKey.join("client", "sfi"): "#d44141",             // streetfortress red
        ValueColorKey.join("client", "acme-inc"): "#dac96eff",        // Volunteering
        ValueColorKey.join("client", "code-corps"): "#26a69a",      // Leisure
        ValueColorKey.join("repo", "company-website"): "#42a5f5",   // Studying
        ValueColorKey.join("repo", "infrastructure"): "#af52de",    // Music Practice
        // Drift matches too — see `proj` above.
        ValueColorKey.join("proj", "company-website"): "#42a5f5",
        ValueColorKey.join("feature", "checkout"): "#f06292",       // Creative Work
        ValueColorKey.join("feature", "search"): "#30b0c7",
        ValueColorKey.join("feature", "billing"): "#ff9500",
        ValueColorKey.join("feature", "moment-tally-api"): "#26a69a",
        ValueColorKey.join("type", "planning"): "#ff9500",
        ValueColorKey.join("type", "coding"): "#007aff",
        ValueColorKey.join("type", "debugging"): "#ff2d55",         // Job Hunt
        ValueColorKey.join("type", "review"): "#34c759",            // Fitness
        ValueColorKey.join("type", "support"): "#af52de",
        ValueColorKey.join("meeting", "standup"): "#ec407a",
        ValueColorKey.join("meeting", "retrospective"): "#af52de",
        ValueColorKey.join("meeting", "handoff"): "#30b0c7",
        ValueColorKey.join("meeting", "release-planning"): "#66bb6a",
        ValueColorKey.join("game", "baldurs-gate"): "#d14931ff",      // Streaming
        ValueColorKey.join("game", "no-mans-sky"): "#4cadeeff",
        ValueColorKey.join("game", "cyberpunk"): "#f7b060",
        ValueColorKey.join("activity", "bike"): "#66bb6a",          // Gardening
        ValueColorKey.join("activity", "run"): "#ff9500",
        ValueColorKey.join("activity", "gym"): "#ff2d55",
        ValueColorKey.join("book", "the-director"): "#5856d6",
        ValueColorKey.join("book", "crux"): "#007aff",
        ValueColorKey.join("book", "the-wayfinder"): "#26a69a",     // the Leisure chip
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
    private static func engagement(_ client: String, _ project: String,
                                   _ key: String, _ value: String) -> [SpanLabel] {
        [SpanLabel(key: "client", value: client),
         SpanLabel(key: "project", value: project),
         SpanLabel(key: key, value: value)]
    }
    private static let blueSkyStandup = engagement("sfi", "moment-tally", "meeting", "standup")
    private static let blueSkyPlanning = engagement("sfi", "moment-tally", "type", "planning")
    private static let blueSkyCoding = engagement("sfi", "moment-tally", "type", "coding")
    private static let meridianRoadmap = engagement("sfi", "meridian", "meeting", "retrospective")
    private static let lighthouseStandup = engagement("acme-inc", "lighthouse", "meeting", "standup")
    private static let lighthouseHandoff = engagement("acme-inc", "lighthouse", "meeting", "handoff")
    private static let lighthouseCoding = engagement("acme-inc", "lighthouse", "type", "coding")
    private static let lighthousePlanning = engagement("acme-inc", "lighthouse", "type", "planning")
    private static let velocityStandup = engagement("code-corps", "velocity-consulting", "meeting", "standup")
    private static let velocityRelease = engagement("code-corps", "velocity-consulting",
                                                    "meeting", "release-planning")
    private static let frontendCoding = [SpanLabel(key: "repo", value: "company-website"),
                                         SpanLabel(key: "feature", value: "checkout"),
                                         SpanLabel(key: "type", value: "coding")]
    private static let frontendReview = [SpanLabel(key: "repo", value: "company-website"),
                                         SpanLabel(key: "feature", value: "checkout"),
                                         SpanLabel(key: "type", value: "review")]
    private static let backendCoding = [SpanLabel(key: "repo", value: "infrastructure"),
                                        SpanLabel(key: "feature", value: "moment-tally-api"),
                                        SpanLabel(key: "type", value: "planning")]
    private static let backendBilling = [SpanLabel(key: "repo", value: "infrastructure"),
                                         SpanLabel(key: "feature", value: "billing"),
                                         SpanLabel(key: "type", value: "coding")]
    // The drift pair: `proj:` where every other span says `repo:` — Label
    // Review's move fixture (`proj: company-website` → `repo:`).
    private static let driftCoding = [SpanLabel(key: "proj", value: "company-website"),
                                      SpanLabel(key: "feature", value: "search"),
                                      SpanLabel(key: "type", value: "coding")]
    private static let driftReview = [SpanLabel(key: "proj", value: "company-website"),
                                      SpanLabel(key: "feature", value: "search"),
                                      SpanLabel(key: "type", value: "review")]
    private static func game(_ value: String) -> [SpanLabel] {
        [SpanLabel(key: "game", value: value)]
    }
    private static func activity(_ value: String) -> [SpanLabel] {
        [SpanLabel(key: "activity", value: value)]
    }
    private static func book(_ value: String) -> [SpanLabel] {
        [SpanLabel(key: "book", value: value)]
    }

    /// Work-day templates, cycled chronologically across the trailing
    /// month's weekdays. Five-day weeks over a four-template cycle mean each
    /// week starts one variant later than the last, so no two charted weeks
    /// look identical — and any six consecutive days contain at least four
    /// weekdays, so every per-variant fixture (the overlap in B, the key
    /// drift in C, the untagged call in D) is launch-date-proof.
    private static let weekdayTemplates: [[Draft]] = [
        // A — a heads-down Moment Tally build day, evening game.
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: blueSkyStandup),
            Draft(startMinute: 585, durationMinutes: 105,
                  labels: engagement("sfi", "moment-tally", "issue", "214")
                      + [SpanLabel(key: "type", value: "coding")],
                  note: "Issue number pasted straight into the quick start"),
            Draft(startMinute: 690, durationMinutes: 30, labels: blueSkyPlanning,
                  note: "Sprint scope"),
            Draft(startMinute: 780, durationMinutes: 120, labels: frontendCoding,
                  note: "In-place editor for running timers"),
            Draft(startMinute: 900, durationMinutes: 30, labels: frontendReview,
                  note: "Review: launcher ＋ card"),
            Draft(startMinute: 960, durationMinutes: 60, labels: blueSkyCoding),
            Draft(startMinute: 1140, durationMinutes: 75, labels: game("baldurs-gate")),
        ],
        // B — meetings and a deploy, with a genuine overlap: the Lighthouse
        // handoff ran while the API deploy was still being watched (the
        // multi-timer story, visible as shared columns in Calendar).
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: lighthouseStandup),
            Draft(startMinute: 600, durationMinutes: 60, labels: meridianRoadmap,
                  note: "Q3 retrospective"),
            Draft(startMinute: 660, durationMinutes: 120, labels: backendCoding,
                  note: "API deploy + watch"),
            Draft(startMinute: 735, durationMinutes: 30, labels: lighthouseHandoff,
                  note: "Handoff — deploy still rolling"),
            Draft(startMinute: 840, durationMinutes: 120, labels: blueSkyCoding,
                  note: "History donuts: per-value colours"),
            Draft(startMinute: 990, durationMinutes: 30, labels: velocityRelease,
                  note: "Release train boarding"),
            Draft(startMinute: 1140, durationMinutes: 45, labels: activity("run")),
        ],
        // C — the drift day: `proj:` where every other span says `repo:`,
        // Label Review's move-to-another-key fixture.
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: blueSkyStandup),
            Draft(startMinute: 585, durationMinutes: 120, labels: driftCoding,
                  note: "Donut hover + selection states"),
            Draft(startMinute: 780, durationMinutes: 60, labels: driftReview),
            Draft(startMinute: 870, durationMinutes: 120,
                  labels: engagement("sfi", "meridian", "issue", "87")
                      + [SpanLabel(key: "type", value: "coding")],
                  note: "Log: minute steppers for start/end"),
            Draft(startMinute: 1000, durationMinutes: 20, labels: lighthousePlanning,
                  note: "Next milestone notes"),
            Draft(startMinute: 1170, durationMinutes: 90, labels: book("crux")),
        ],
        // D — a lighter day with an untagged phone call (the ad-hoc story:
        // a blank-timer span left as it was captured).
        [
            Draft(startMinute: 570, durationMinutes: 15, labels: lighthouseStandup),
            Draft(startMinute: 600, durationMinutes: 150, labels: backendBilling,
                  note: "Label Review: drag values between keys"),
            Draft(startMinute: 810, durationMinutes: 30,
                  note: "Phone call — forgot the labels"),
            Draft(startMinute: 870, durationMinutes: 60, labels: lighthouseCoding),
            Draft(startMinute: 945, durationMinutes: 45, labels: frontendReview,
                  note: "Landing-page copy pass"),
            Draft(startMinute: 1050, durationMinutes: 45, labels: activity("gym")),
        ],
    ]

    /// Weekend templates — leisure-only on purpose, so the History day bars
    /// show the work-day clustering and the quick-labels-only sets (Gaming,
    /// Workout, Reading) own the weekends.
    private static let weekendTemplates: [[Draft]] = [
        [
            Draft(startMinute: 600, durationMinutes: 60, labels: activity("bike"),
                  note: "Morning loop"),
            Draft(startMinute: 780, durationMinutes: 150, labels: game("no-mans-sky"),
                  note: "Weekend expedition"),
            Draft(startMinute: 990, durationMinutes: 90, labels: book("the-director")),
        ],
        [
            Draft(startMinute: 630, durationMinutes: 45, labels: activity("run")),
            Draft(startMinute: 840, durationMinutes: 90, labels: game("cyberpunk")),
            Draft(startMinute: 1020, durationMinutes: 60, labels: book("the-wayfinder"),
                  note: "One more chapter"),
        ],
    ]

    /// Today, laid out backwards from `now` (in minutes) so it always fits
    /// whatever the launch time is; a nil duration is a *running* span. The
    /// last two power the live menu-bar timer and the popover's multi-timer
    /// rows; the support span matches no saved set, so its Log row shows the
    /// save-as-set ＋; the empty entry is today's ad-hoc unlabelled span.
    private static let todayTemplate: [(minutesBeforeNow: Int, durationMinutes: Int?,
                                        labels: [SpanLabel], note: String)] = [
        (220, 75, engagement("sfi", "moment-tally", "issue", "231")
             + [SpanLabel(key: "type", value: "coding")], "README screenshot pass"),
        (130, 20, velocityStandup, ""),
        (105, 15, [], ""),
        (80, 25, [SpanLabel(key: "repo", value: "company-website"),
                  SpanLabel(key: "type", value: "support")], "Crash report triage"),
        (42, 0, blueSkyCoding, "Popover: running-row editor"),
        (9, nil, backendCoding, ""),
    ]

    /// The full seed for the trailing month: thirty templated past days
    /// (weekday variants cycled in chronological order, weekend days
    /// leisure-only) plus today anchored to `now`.
    static func spans(now: Date, calendar: Calendar = .current) -> [SeedSpan] {
        var result: [SeedSpan] = []
        var weekdayIndex = 0
        var weekendIndex = 0
        for offset in -30...(-1) {
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
