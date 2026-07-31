import Foundation
import GRDB
import Testing
@testable import PrimeTime
@testable import PrimeTimeCore

/// The demo seeder (#39): activation parsing, determinism, the content
/// fixtures every surface depends on, and isolation from the real store.
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

    /// Mid-week reference: the trailing week is Thu–Tue behind a Wednesday,
    /// so all four weekday templates and both weekend templates appear.
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
        // Thu(A 6) + Fri(B 6) + Sat(W1 2) + Sun(W2 3) + Mon(C 5) + Tue(D 5)
        // + today(6).
        #expect(spans.count == 33)
        #expect(DemoSeed.tagSets.count == 8)
        #expect(Set(DemoSeed.tagSets.compactMap(\.symbolName)).count == 8)  // distinct symbols
        #expect(DemoSeed.labelDefinitions.count == 7)
        #expect(DemoSeed.valueColors.count == 17)
        // Notes on several spans, so Log and Calendar popovers have texture.
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

            // Two unlabelled ad-hoc spans (blank-timer story).
            #expect(spans.filter(\.labels.isEmpty).count == 2)

            // The proj/project drift for Tag Review — both spellings in use.
            let keys = spans.flatMap(\.labels).map(\.key)
            #expect(keys.filter { $0 == "proj" }.count == 3)
            #expect(keys.contains("project"))

            // At least one genuine overlap among *finished* spans (the
            // running pair overlaps trivially).
            let finished = spans.filter { $0.end != nil }
            let overlaps = finished.contains { a in
                finished.contains { b in
                    a.start < b.start && b.start < a.end!
                }
            }
            #expect(overlaps)

            // Everything inside the trailing week, nothing in the future.
            #expect(spans.allSatisfy {
                $0.start >= now.addingTimeInterval(-7 * 86_400) && $0.start <= now
            })
            #expect(spans.allSatisfy { ($0.end ?? now) <= now })
        }
    }

    @Test func valueColorsDifferentiateRepoWebsiteFromRepoServer() {
        let colors = DemoSeed.valueColors
        let website = colors[ValueColorKey.join("repo", "website")]
        let server = colors[ValueColorKey.join("repo", "server")]
        #expect(website != nil && server != nil && website != server)
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
