import Foundation

// MARK: - Domain types
//
// The app's own vocabulary: a *label* is a `key: value` dimension attached to
// a timespan, so time can be sliced along any axis later (the Prometheus
// mental model — time series with dimensions). Backends translate these to and
// from their own wire shapes; nothing here knows about GraphQL or RFC3339.

/// The signed-in account a backend serves data for. Decodable because its wire
/// shape already is the domain shape — no separate DTO needed.
struct User: Decodable, Equatable {
    let id: Int
    let name: String
    let admin: Bool
}

/// A key/value pair attached to a timespan — e.g. `repo: primetime`.
struct SpanLabel: Hashable {
    let key: String
    let value: String
}

/// A label key's definition: the key itself plus its display colour (a hex
/// string like "#2196f3"). Colours are stored per *key*; per-value colours are
/// a client-side overlay (see `AppModel.valueColors`). Codable so the local
/// store can persist it directly as a GRDB record — the type is its own row.
struct LabelDefinition: Hashable, Codable {
    let key: String
    let color: String
}

/// A tracked interval of time, possibly still running, with its labels.
struct TimeSpan: Identifiable, Equatable {
    let id: Int
    let start: Date
    let end: Date?      // nil == currently running
    let note: String
    let labels: [SpanLabel]

    var isRunning: Bool { end == nil }
}

// MARK: - Paging

/// An opaque paging token. Backends serialise whatever state their own page
/// walk needs into `rawValue` (traggo: its stable-cursor JSON); callers only
/// hand a token back to the backend that minted it.
struct PageToken: Equatable {
    let rawValue: String
}

/// One page of finished timespans, plus the token for the next page — nil when
/// the walk is complete.
struct TimeSpanPage {
    let timeSpans: [TimeSpan]
    let nextPage: PageToken?
}

// MARK: - Backend

/// The storage seam between the state layer and wherever timespans actually
/// live. Today the only implementation is `TraggoClient` (a traggo server over
/// GraphQL); a local store and a PrimeTime sync backend implement the same
/// surface later.
///
/// Deliberately data-only: session lifecycle (login, logout, tokens) is a
/// per-backend concern owned by whoever constructs the backend — a local store
/// has no notion of logging in.
protocol Backend {
    /// The user this backend serves, or nil when it isn't ready to (e.g. an
    /// expired token). Doubles as the readiness probe.
    func currentUser() async throws -> User?

    /// All currently-running timespans (end == nil).
    func timers() async throws -> [TimeSpan]

    /// Every known label definition (keys with colours).
    func labelDefinitions() async throws -> [LabelDefinition]

    /// Register a new label key with a colour. Backends may require this
    /// before the key can appear on a timespan (traggo rejects unknown keys).
    func createLabelDefinition(key: String, color: String) async throws

    /// Change the colour of an existing label key, everywhere it's used.
    func updateLabelDefinition(key: String, color: String) async throws

    /// Start a running timespan (no end time).
    func startTimeSpan(start: Date, labels: [SpanLabel], note: String) async throws -> TimeSpan

    /// Update a timespan in place. Every field is written, so callers pass the
    /// current values for anything they're not changing. A nil `end` leaves
    /// the timespan running.
    func updateTimeSpan(id: Int, start: Date, end: Date?, labels: [SpanLabel], note: String) async throws -> TimeSpan

    /// Stop a running timespan.
    func stopTimeSpan(id: Int, end: Date) async throws -> TimeSpan

    /// Delete a timespan.
    func removeTimeSpan(id: Int) async throws

    /// One page of *finished* timespans overlapping [from, to], newest first;
    /// pass the previous page's `nextPage` token to continue the walk. Running
    /// timespans are excluded — merge in `timers()` for a complete picture.
    func timeSpans(from: Date, to: Date, page: PageToken?) async throws -> TimeSpanPage
}
