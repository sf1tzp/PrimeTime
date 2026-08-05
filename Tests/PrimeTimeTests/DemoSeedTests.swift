import Foundation
import GRDB
import Testing
@testable import PrimeTime
@testable import PrimeTimeCore

/// The demo seeder (#39, renovated in #172): activation parsing,
/// determinism, the content fixtures every surface depends on, and
/// isolation from the real store.
@Suite struct DemoSeedTests {

    /// Gregorian + UTC so day layout (which offsets are weekends) doesn't
    /// depend on the machine running the tests.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month,
                                                day: day, hour: hour))!
    }

    /// Mid-week reference: the trailing month behind a Wednesday starts on a
    /// Monday, so the weekday-template cycle is easy to count by hand.
    private var wednesday: Date { date(2026, 7, 29, 10) }
    /// A second layout — Sunday evening — to prove the fixtures are
    /// launch-date-proof, not artifacts of one weekday arrangement.
    private var sunday: Date { date(2026, 8, 2, 21) }

    private func seed(now: Date) -> [DemoSeed.SeedSpan] {
        DemoSeed.spans(now: now, calendar: Self.calendar)
    }

    // MARK: Activation

    @Test func activationParsesEnvironmentAndArguments() {
        #expect(DemoMode.isActive(environment: ["PRIMETIME_DEMO": "1"], arguments: []))
        #expect(DemoMode.isActive(environment: ["PRIMETIME_DEMO": "true"], arguments: []))
        #expect(DemoMode.isActive(environment: [:], arguments: ["app", "--demo"]))
        #expect(!DemoMode.isActive(environment: ["PRIMETIME_DEMO": "0"], arguments: []))
        #expect(!DemoMode.isActive(environment: ["PRIMETIME_DEMO": ""], arguments: []))
        #expect(!DemoMode.isActive(environment: [:], arguments: ["app"]))
    }

    // MARK: Determinism

    @Test func seedIsDeterministicForAFixedReferenceDate() {
        #expect(seed(now: wednesday) == seed(now: wednesday))
    }

    @Test func writeRoundTripsTheGeneratedSeed() async throws {
        let backend = try LocalBackend(DatabaseQueue())
        try DemoSeed.write(to: backend, now: wednesday, calendar: Self.calendar)

        let finished = try await backend.timeSpans(from: .distantPast,
                                                   to: .distantFuture, page: nil).timeSpans
        let running = try await backend.timers()
        let stored = Set((finished + running).map {
            DemoSeed.SeedSpan(start: $0.start, end: $0.end, labels: $0.labels, note: $0.note)
        })
        #expect(stored == Set(seed(now: wednesday)))

        #expect(try backend.loadTagSets().map(\.name) == DemoSeed.tagSets.map(\.name))
        #expect(try await backend.labelDefinitions().count == DemoSeed.labelDefinitions.count)
        #expect(try backend.loadValueColors() == DemoSeed.valueColors)
    }

    // MARK: Content fixtures

    @Test func contentCountsForTheMidWeekLayout() {
        let spans = seed(now: wednesday)
        // The trailing month behind Wed 2026-07-29 runs Mon Jun 29 – Tue
        // Jul 28: 22 weekdays cycling A,B,C,D (A×6 + B×6 at 7 spans, C×5 +
        // D×5 at 6 spans = 144) + 8 weekend days alternating W1/W2 (24)
        // + today (6).
        #expect(spans.count == 174)
        #expect(DemoSeed.tagSets.count == 9)
        #expect(Set(DemoSeed.tagSets.compactMap(\.symbolName)).count == 9)  // distinct symbols
        #expect(DemoSeed.labelDefinitions.count == 11)
        #expect(DemoSeed.valueColors.count == 31)
        // Notes on many spans, so Log and Calendar popovers have texture.
        #expect(spans.filter { !$0.note.isEmpty }.count >= 10)
    }

    @Test func fixturesHoldAcrossWeekLayouts() {
        for now in [wednesday, sunday] {
            let spans = seed(now: now)

            // Two running spans (live menu-bar timer + multi-timer popover),
            // started recently enough to read as "just now".
            let running = spans.filter { $0.end == nil }
            #expect(running.count == 2)
            #expect(running.allSatisfy {
                $0.start > now.addingTimeInterval(-3600) && $0.start <= now
            })

            // Unlabelled ad-hoc spans (blank-timer story): one per D-day
            // plus one today.
            #expect(spans.filter(\.labels.isEmpty).count >= 5)

            // The proj/repo drift for Label Review — `proj: company-website`
            // spans to move onto the canonical `repo:` key (#172's capture).
            let labels = spans.flatMap(\.labels)
            #expect(labels.filter { $0.key == "proj" && $0.value == "company-website" }
                .count >= 8)
            #expect(labels.contains { $0.key == "repo" && $0.value == "company-website" })

            // History's combined view needs real co-occurrence on all three
            // showcased pairings: type × project, type × client,
            // meeting × client.
            func cooccur(_ a: String, _ b: String) -> Bool {
                spans.contains { span in
                    span.labels.contains { $0.key == a } && span.labels.contains { $0.key == b }
                }
            }
            #expect(cooccur("type", "project"))
            #expect(cooccur("type", "client"))
            #expect(cooccur("meeting", "client"))

            // Every leisure chip value shows up in history, so the Launcher
            // hover video always has populated cards to point at.
            let values = { (key: String) in Set(labels.filter { $0.key == key }.map(\.value)) }
            #expect(values("game") == ["baldurs-gate", "no-mans-sky", "cyberpunk"])
            #expect(values("activity") == ["bike", "run", "gym"])
            #expect(values("book") == ["the-director", "crux", "the-wayfinder"])

            // At least one genuine overlap among *finished* spans (the
            // running pair overlaps trivially).
            let finished = spans.filter { $0.end != nil }
            let overlaps = finished.contains { a in
                finished.contains { b in
                    a.start < b.start && b.start < a.end!
                }
            }
            #expect(overlaps)

            // Everything inside the trailing month, nothing in the future.
            #expect(spans.allSatisfy {
                $0.start >= now.addingTimeInterval(-31 * 86_400) && $0.start <= now
            })
            #expect(spans.allSatisfy { ($0.end ?? now) <= now })
        }
    }

    @Test func everySetCarriesItsQuickLabels() {
        for set in DemoSeed.tagSets {
            let quick = DemoSeed.quickLabels(forSetNamed: set.name)
            #expect(quick?.isEmpty == false, "\(set.name) has no quick labels")
        }
        // The work sets carry the type trio; the full-service client sets
        // add the meeting chips on top.
        let type = DemoSeed.quickLabels(forSetNamed: "Frontend Work")!
        #expect(type.map(\.value) == ["planning", "coding", "review"])
        #expect(type.allSatisfy { $0.key == "type" })
        #expect(DemoSeed.quickLabels(forSetNamed: "Blue Sky")!.count == 6)
        // The leisure sets are quick-labels-only: chips with no presets, and
        // a colorHex so their launcher cards aren't accent-grey.
        for name in ["Gaming", "Workout", "Reading"] {
            let set = DemoSeed.tagSets.first { $0.name == name }!
            #expect(set.tags.isEmpty)
            #expect(set.colorHex != nil)
        }
    }

    @Test func valuelessLabelsSeedTheFillInPerStartStory() {
        func rows(_ name: String) -> [TagRow] {
            DemoSeed.tagSets.first { $0.name == name }!.tags
        }
        // The shared value-less `feature:` on the work pair (#149/#162)...
        for name in ["Frontend Work", "Backend Work"] {
            #expect(rows(name).contains { $0.key == "feature" && $0.value.isEmpty })
        }
        // ...and value-less `repo:`/`issue:` on the full-service client sets.
        for name in ["Blue Sky", "Meridian", "Lighthouse"] {
            #expect(rows(name).contains { $0.key == "repo" && $0.value.isEmpty })
            #expect(rows(name).contains { $0.key == "issue" && $0.value.isEmpty })
        }
    }

    @Test func valueColorsDifferentiateTheCompanyRepos() {
        let colors = DemoSeed.valueColors
        let website = colors[ValueColorKey.join("repo", "company-website")]
        let server = colors[ValueColorKey.join("repo", "company-server")]
        #expect(website != nil && server != nil && website != server)
        // The drifted spelling matches the canonical one, so the mistake
        // reads in Label Review rather than on every pill.
        #expect(colors[ValueColorKey.join("proj", "company-website")] == website)
    }

    // MARK: Isolation from the real store

    @Test func demoDatabaseLivesBesideButNeverAtTheRealPath() throws {
        let demo = try LocalBackend.demoDatabaseURL()
        let real = try LocalBackend.defaultDatabaseURL()
        #expect(demo.lastPathComponent == "demo.sqlite")
        #expect(demo != real)
        #expect(demo.deletingLastPathComponent() == real.deletingLastPathComponent())
    }

    @Test func demoStoreIsRebuiltFromScratchAtItsOwnPath() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DemoSeedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("demo.sqlite")

        // Seeding writes only to the path it was given.
        let first = try LocalBackend.demo(at: url, now: wednesday, calendar: Self.calendar)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .allSatisfy { $0.hasPrefix("demo.sqlite") })

        // A "previous session" leaves extra data behind...
        _ = try await first.startTimeSpan(start: wednesday, labels: [], note: "stale")

        // ...and the next demo launch starts over from exactly the seed.
        let second = try LocalBackend.demo(at: url, now: wednesday, calendar: Self.calendar)
        let count = try await second.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_span")!
        }
        #expect(count == seed(now: wednesday).count)

        // The demo never imports the user's presets (legacyDefaults is nil):
        // its tag sets are the demo's, nothing legacy.
        #expect(try second.loadTagSets().map(\.name) == DemoSeed.tagSets.map(\.name))
    }
}
