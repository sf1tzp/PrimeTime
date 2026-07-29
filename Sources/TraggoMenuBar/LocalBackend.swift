import Foundation
import GRDB

// MARK: - Record rows
//
// The schema speaks the *label* vocabulary (#27) even while UI copy still says
// "tag" — a schema is the one place a rename would churn data, so it's born
// with the final words. `LabelDefinition` persists directly (it *is* its row);
// `TimeSpan` doesn't, because its labels live in a child table, so a pair of
// private row types bridges it.

extension LabelDefinition: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "label_definition" }
}

/// One `time_span` row — the span without its labels.
private struct TimeSpanRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "time_span"
    var id: Int64?
    var start: Date
    var end: Date?     // NULL = currently running
    var note: String

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// One label on one span (`time_span_label`). Label order within a span is the
/// insertion order (rowid), so a span's labels render the way they were saved.
private struct SpanLabelRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "time_span_label"
    var spanId: Int64
    var key: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case spanId = "span_id", key, value
    }
}

/// A per-`key: value` colour override (`value_color`) — first-class here,
/// unlike traggo where it's a client-side overlay on top of per-key colours.
private struct ValueColorRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "value_color"
    var key: String
    var value: String
    var color: String
}

/// A saved tag set (`label_set`). `id` is the TagSet's UUID string so set
/// identity survives the round trip (quick-start matching, pane selection).
private struct LabelSetRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "label_set"
    var id: String
    var name: String
    var symbol: String?
    var position: Int
}

/// One member tag of a set (`label_set_member`), ordered by `position`.
/// Key/value are stored as typed — un-normalised — matching what the legacy
/// UserDefaults JSON kept; normalisation stays at the `TagSet.labels` boundary.
private struct LabelSetMemberRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "label_set_member"
    var setId: String
    var position: Int
    var key: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case setId = "set_id", position, key, value
    }
}

// MARK: - LocalBackend

/// The serverless `Backend`: a single SQLite file under Application Support,
/// via GRDB. Everything the traggo backend stores remotely lives here instead —
/// plus the things that were only ever local (tag sets, value colours), which
/// move out of UserDefaults and into the same file so local mode has one
/// backup-able artifact.
final class LocalBackend: Backend {
    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let dbQueue: DatabaseQueue
    /// Where the store lives on disk; nil for in-memory (tests).
    let databaseURL: URL?
    /// Spans per page of `timeSpans(from:to:page:)`. Internal so tests can
    /// shrink it to exercise the page walk with few rows.
    var pageSize = 200

    /// The store has no login — the "account" is whoever owns the Mac.
    /// A stable id keeps `TimeSpan`/`User` shapes identical across backends.
    static let localUser = User(
        id: 1,
        name: NSFullUserName().isEmpty ? NSUserName() : NSFullUserName(),
        admin: true)

    /// Opens (creating on first run) the default on-disk store.
    convenience init(legacyDefaults: UserDefaults = .standard) throws {
        let url = try Self.defaultDatabaseURL()
        try self.init(DatabaseQueue(path: url.path), databaseURL: url,
                      legacyDefaults: legacyDefaults)
    }

    /// Designated initialiser; tests pass an in-memory `DatabaseQueue()`.
    init(_ dbQueue: DatabaseQueue, databaseURL: URL? = nil,
         legacyDefaults: UserDefaults? = nil) throws {
        self.dbQueue = dbQueue
        self.databaseURL = databaseURL
        try Self.migrator(legacyDefaults: legacyDefaults).migrate(dbQueue)
    }

    /// `~/Library/Application Support/<bundle id>/primetime.sqlite`. The SPM
    /// executable has no bundle identifier until the app is bundled, so fall
    /// back to the target name; the *file* name is already the product's so a
    /// later rename doesn't have to move data.
    static func defaultDatabaseURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "TraggoMenuBar", isDirectory: true)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        return directory.appendingPathComponent("primetime.sqlite")
    }

    // MARK: Migrations

    /// The schema is applied through DatabaseMigrator from day one so phase 6
    /// can add sync metadata (server id, dirty flag, tombstone) as a plain
    /// later migration instead of a rebuild.
    private static func migrator(legacyDefaults: UserDefaults?) -> DatabaseMigrator {
        // Read the legacy values up front: migration closures are @Sendable
        // and UserDefaults isn't, but the plain values it yields are.
        let legacyPresets = legacyDefaults?.data(forKey: "presets")
        let legacyColors = legacyDefaults?.dictionary(forKey: "valueColors") as? [String: String]

        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-schema") { db in
            try db.create(table: "time_span") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start", .datetime).notNull().indexed()
                t.column("end", .datetime)                     // NULL = running
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(table: "time_span_label") { t in
                t.column("span_id", .integer).notNull().indexed()
                    .references("time_span", onDelete: .cascade)
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
            }
            try db.create(table: "label_definition") { t in
                t.column("key", .text).primaryKey()
                t.column("color", .text).notNull()
            }
            try db.create(table: "value_color") { t in
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
                t.column("color", .text).notNull()
                t.primaryKey(["key", "value"])
            }
            try db.create(table: "label_set") { t in
                t.column("id", .text).primaryKey()             // TagSet UUID
                t.column("name", .text).notNull()
                t.column("symbol", .text)                      // nil = default
                t.column("position", .integer).notNull()       // launcher order
            }
            try db.create(table: "label_set_member") { t in
                t.column("set_id", .text).notNull().indexed()
                    .references("label_set", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("key", .text).notNull()
                t.column("value", .text).notNull()
            }
        }

        // One-time import of what used to be the app's only local persistence.
        // Running it as a migration gives the exactly-once semantics for free
        // (recorded in grdb_migrations, per database file). The legacy keys
        // are copied, not cleared: traggo mode still reads them, so switching
        // backends never loses the UserDefaults-era data.
        migrator.registerMigration("v1-import-user-defaults") { db in
            let sets: [TagSet]
            if let data = legacyPresets,
               let decoded = try? JSONDecoder().decode([TagSet].self, from: data) {
                sets = decoded
            } else {
                // Fresh install: seed the same samples first-run always had.
                sets = TagSet.samples
            }
            try insert(tagSets: sets, db)

            for (composite, color) in legacyColors ?? [:] {
                guard let (key, value) = ValueColorKey.split(composite) else { continue }
                try ValueColorRow(key: key, value: value, color: color).insert(db)
            }
        }

        return migrator
    }

    // MARK: Backend — session

    func currentUser() async throws -> User? { Self.localUser }

    // MARK: Backend — label definitions

    func labelDefinitions() async throws -> [LabelDefinition] {
        try await dbQueue.read { db in
            try LabelDefinition.order(Column("key")).fetchAll(db)
        }
    }

    func createLabelDefinition(key: String, color: String) async throws {
        try await dbQueue.write { db in
            // A duplicate insert throws (unique key), matching traggo's
            // create-vs-update split that callers already navigate.
            try LabelDefinition(key: key, color: color).insert(db)
        }
    }

    func updateLabelDefinition(key: String, color: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE label_definition SET color = ? WHERE key = ?",
                           arguments: [color, key])
            guard db.changesCount > 0 else {
                throw Error(message: "No such tag key: \(key)")
            }
        }
    }

    // MARK: Backend — timespans

    func timers() async throws -> [TimeSpan] {
        try await dbQueue.read { db in
            let rows = try TimeSpanRow
                .filter(Column("end") == nil)
                .order(Column("start"))
                .fetchAll(db)
            return try Self.spans(for: rows, db)
        }
    }

    func startTimeSpan(start: Date, labels: [SpanLabel], note: String) async throws -> TimeSpan {
        try await dbQueue.write { db in
            var row = TimeSpanRow(id: nil, start: start, end: nil, note: note)
            try row.insert(db)
            try Self.insert(labels: labels, spanId: row.id!, db)
            return try Self.span(for: row, db)
        }
    }

    func updateTimeSpan(id: Int, start: Date, end: Date?, labels: [SpanLabel], note: String) async throws -> TimeSpan {
        try await dbQueue.write { db in
            guard var row = try TimeSpanRow.fetchOne(db, key: Int64(id)) else {
                throw Error(message: "No such timespan: \(id)")
            }
            row.start = start
            row.end = end
            row.note = note
            try row.update(db)
            // Labels are replaced wholesale — the protocol's "every field is
            // written" contract — which also renumbers their display order.
            try SpanLabelRow.filter(Column("span_id") == Int64(id)).deleteAll(db)
            try Self.insert(labels: labels, spanId: Int64(id), db)
            return try Self.span(for: row, db)
        }
    }

    func stopTimeSpan(id: Int, end: Date) async throws -> TimeSpan {
        try await dbQueue.write { db in
            guard var row = try TimeSpanRow.fetchOne(db, key: Int64(id)) else {
                throw Error(message: "No such timespan: \(id)")
            }
            row.end = end
            try row.update(db)
            return try Self.span(for: row, db)
        }
    }

    func removeTimeSpan(id: Int) async throws {
        try await dbQueue.write { db in
            guard try TimeSpanRow.deleteOne(db, key: Int64(id)) else {
                throw Error(message: "No such timespan: \(id)")
            }
            // time_span_label rows follow via ON DELETE CASCADE.
        }
    }

    /// Keyset pagination over finished spans overlapping [from, to], newest
    /// first: the token carries the last row's (start, id) and the next page
    /// resumes strictly after it. Unlike offsets, this stays stable when spans
    /// are inserted or deleted mid-walk — the Tag Review scan mutates nothing,
    /// but Approve Changes could interleave with a running History load.
    func timeSpans(from: Date, to: Date, page: PageToken?) async throws -> TimeSpanPage {
        let cursor = page.flatMap(LocalCursor.init)
        let pageSize = pageSize
        return try await dbQueue.read { db in
            var request = TimeSpanRow
                .filter(Column("end") != nil)
                .filter(Column("start") <= to && Column("end") >= from)
            if let cursor {
                request = request.filter(
                    Column("start") < cursor.start
                        || (Column("start") == cursor.start && Column("id") < cursor.id))
            }
            // Fetch one extra row purely to learn whether more exist, so the
            // last full page doesn't mint a token to an empty page.
            let rows = try request
                .order(Column("start").desc, Column("id").desc)
                .limit(pageSize + 1)
                .fetchAll(db)
            let pageRows = Array(rows.prefix(pageSize))
            let next: PageToken? = rows.count > pageSize
                ? LocalCursor(start: pageRows.last!.start, id: pageRows.last!.id!).pageToken
                : nil
            return TimeSpanPage(timeSpans: try Self.spans(for: pageRows, db),
                                nextPage: next)
        }
    }

    // MARK: Tag sets + value colours (local-only surface, not part of Backend)
    //
    // Synchronous by design: AppModel persists these from didSet observers on
    // the main actor, exactly like the UserDefaults writes they replace, and
    // the tables are a few dozen rows at most.

    func loadTagSets() throws -> [TagSet] {
        try dbQueue.read { db in
            let sets = try LabelSetRow.order(Column("position")).fetchAll(db)
            let members = try LabelSetMemberRow.order(Column("position")).fetchAll(db)
            let bySet = Dictionary(grouping: members, by: \.setId)
            return sets.map { row in
                TagSet(id: UUID(uuidString: row.id) ?? UUID(),
                       name: row.name,
                       tags: (bySet[row.id] ?? []).map { TagRow(key: $0.key, value: $0.value) },
                       symbolName: row.symbol)
            }
        }
    }

    /// Replace-all in one transaction — the same snapshot semantics as the
    /// UserDefaults JSON blob this supersedes, and position renumbering falls
    /// out for free.
    func saveTagSets(_ sets: [TagSet]) throws {
        try dbQueue.write { db in
            try LabelSetRow.deleteAll(db)   // members cascade
            try Self.insert(tagSets: sets, db)
        }
    }

    /// In AppModel's composite-key dictionary form (`key␟value` → hex), so the
    /// in-memory representation is identical whichever store backs it.
    func loadValueColors() throws -> [String: String] {
        try dbQueue.read { db in
            var colors: [String: String] = [:]
            for row in try ValueColorRow.fetchAll(db) {
                colors[ValueColorKey.join(row.key, row.value)] = row.color
            }
            return colors
        }
    }

    func saveValueColors(_ colors: [String: String]) throws {
        try dbQueue.write { db in
            try ValueColorRow.deleteAll(db)
            for (composite, color) in colors {
                guard let (key, value) = ValueColorKey.split(composite) else { continue }
                try ValueColorRow(key: key, value: value, color: color).insert(db)
            }
        }
    }

    // MARK: Demo seeding (see DemoMode.swift)
    //
    // Synchronous like the tag-set/value-colour surface, and for the same
    // reason: the seeder runs inside the (main-actor) backend activation.
    // These live here rather than with the seeder because they need the
    // file-private row types.

    /// Replace every label definition in one transaction.
    func replaceLabelDefinitions(_ definitions: [LabelDefinition]) throws {
        try dbQueue.write { db in
            try LabelDefinition.deleteAll(db)
            for definition in definitions {
                try definition.insert(db)
            }
        }
    }

    /// Replace every timespan (labels cascade) with the given seed rows, in
    /// one transaction.
    func replaceTimeSpans(with spans: [DemoSeed.SeedSpan]) throws {
        try dbQueue.write { db in
            try TimeSpanRow.deleteAll(db)
            for span in spans {
                var row = TimeSpanRow(id: nil, start: span.start, end: span.end,
                                      note: span.note)
                try row.insert(db)
                try Self.insert(labels: span.labels, spanId: row.id!, db)
            }
        }
    }

    // MARK: Shared row plumbing

    private static func insert(tagSets sets: [TagSet], _ db: Database) throws {
        for (position, set) in sets.enumerated() {
            try LabelSetRow(id: set.id.uuidString, name: set.name,
                            symbol: set.symbolName, position: position).insert(db)
            for (memberPosition, tag) in set.tags.enumerated() {
                try LabelSetMemberRow(setId: set.id.uuidString, position: memberPosition,
                                      key: tag.key, value: tag.value).insert(db)
            }
        }
    }

    private static func insert(labels: [SpanLabel], spanId: Int64, _ db: Database) throws {
        for label in labels {
            try SpanLabelRow(spanId: spanId, key: label.key, value: label.value).insert(db)
        }
    }

    private static func span(for row: TimeSpanRow, _ db: Database) throws -> TimeSpan {
        try spans(for: [row], db).first!
    }

    /// Assemble domain `TimeSpan`s: one labels query for the whole page rather
    /// than one per span.
    private static func spans(for rows: [TimeSpanRow], _ db: Database) throws -> [TimeSpan] {
        guard !rows.isEmpty else { return [] }
        let ids = rows.compactMap(\.id)
        let labelRows = try SpanLabelRow
            .filter(ids.contains(Column("span_id")))
            .order(Column("rowid"))
            .fetchAll(db)
        var labels: [Int64: [SpanLabel]] = [:]
        for row in labelRows {
            labels[row.spanId, default: []].append(SpanLabel(key: row.key, value: row.value))
        }
        return rows.map { row in
            TimeSpan(id: Int(row.id!), start: row.start, end: row.end,
                     note: row.note, labels: labels[row.id!] ?? [])
        }
    }
}

// MARK: - Paging token

/// The local backend's paging state, riding opaquely in `PageToken` the same
/// way traggo's cursor does: JSON, decodable only by the backend that minted
/// it. `start` round-trips exactly because both sides carry GRDB's stored
/// (millisecond) precision.
private struct LocalCursor: Codable {
    let start: Date
    let id: Int64

    var pageToken: PageToken? {
        guard let data = try? JSONEncoder().encode(self),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return PageToken(rawValue: raw)
    }

    /// Nil for tokens this backend didn't mint; callers only hand back our own.
    init?(_ token: PageToken) {
        guard let data = token.rawValue.data(using: .utf8),
              let cursor = try? JSONDecoder().decode(LocalCursor.self, from: data) else { return nil }
        self = cursor
    }

    init(start: Date, id: Int64) {
        self.start = start
        self.id = id
    }
}
