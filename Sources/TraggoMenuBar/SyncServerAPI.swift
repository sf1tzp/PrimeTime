import Foundation

// MARK: - Remote record shapes
//
// What the sync engine sees of the server: domain values plus `updatedAt`,
// the server-side half of last-writer-wins (server write time, whole
// seconds — see server/docs/api-v1.md "Sync"). These are *not* wire DTOs;
// `PrimeTimeClient` maps GraphQL payloads into them at its boundary, and the
// engine's tests implement the same protocol with an in-memory fake.

struct RemoteTimeSpan: Equatable {
    let id: Int
    let start: Date
    let end: Date?         // nil == running
    let note: String
    let labels: [SpanLabel]
    let updatedAt: Date
}

/// A timespan deletion the server remembers (a tombstone).
struct RemoteDeletion: Equatable {
    let id: Int
    let deletedAt: Date
}

/// One page of the timespan delta feed.
struct RemoteTimeSpanChanges {
    let timeSpans: [RemoteTimeSpan]
    let deleted: [RemoteDeletion]
    let hasMore: Bool
    let now: Date
}

struct RemoteValueColor: Equatable {
    let value: String
    let color: String
    let updatedAt: Date
}

struct RemoteLabelDefinition: Equatable {
    let key: String
    let color: String
    let valueColors: [RemoteValueColor]
    let updatedAt: Date
}

/// A label set as the server holds it; `labels` are the ordered members.
/// Position on the server is the index in the `labelSets()` array.
struct RemoteLabelSet: Equatable {
    let id: Int
    let name: String
    let symbolName: String
    let labels: [SpanLabel]
    let updatedAt: Date
}

struct RemotePreferences: Equatable {
    let colorByValue: Bool
    let menuLabelSetLimit: Int
    /// Zero-adjacent (`.distantPast` after mapping) when never set — any
    /// device's real edit wins over never-written defaults.
    let updatedAt: Date
}

/// Marks an error as a server-side *rejection* (a GraphQL error: "does not
/// exist", "already exists") as opposed to a transport failure. The engine
/// tolerates rejections where they mean the work is moot (deleting an
/// already-absent record) and falls back where they mean a race (creating a
/// key another device just created); transport failures abort the run and
/// everything stays queued.
protocol ServerRejection: Error {}

// MARK: - The server surface the engine syncs against

/// The v1 operations reconciliation needs — implemented for real by
/// `PrimeTimeClient` and in-process by the tests' fake server. Timespans
/// sync by delta feed; everything else by snapshot.
protocol SyncServerAPI {
    /// Session probe: the signed-in user, or nil when the token is dead.
    func currentUser() async throws -> User?

    // Pull
    func timeSpanChanges(since: Date, afterId: Int) async throws -> RemoteTimeSpanChanges
    func labelDefinitions() async throws -> [RemoteLabelDefinition]
    func labelSets() async throws -> [RemoteLabelSet]
    func userPreferences() async throws -> RemotePreferences

    // Push — timespans
    func createTimeSpan(start: Date, end: Date?, labels: [SpanLabel], note: String) async throws -> Int
    func updateTimeSpan(id: Int, start: Date, end: Date?, labels: [SpanLabel], note: String) async throws
    func removeTimeSpan(id: Int) async throws

    // Push — label definitions and value colours
    func createLabelDefinition(key: String, color: String) async throws
    func updateLabelDefinition(key: String, color: String) async throws
    func setLabelValueColor(key: String, value: String, color: String) async throws
    func clearLabelValueColor(key: String, value: String) async throws

    // Push — label sets (position rides along, see the v1 position args)
    func createLabelSet(name: String, symbolName: String, labels: [SpanLabel], position: Int) async throws -> Int
    func updateLabelSet(id: Int, name: String, symbolName: String, labels: [SpanLabel], position: Int) async throws
    func removeLabelSet(id: Int) async throws

    // Push — preferences
    func setUserPreferences(colorByValue: Bool, menuLabelSetLimit: Int) async throws
}
