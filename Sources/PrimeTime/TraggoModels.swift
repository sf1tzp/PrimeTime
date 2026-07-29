import Foundation

// Wire DTOs for the traggo GraphQL API, mirroring schema.graphql — which is
// why this layer says "tag" while the domain (Backend.swift) says "label".
// `TraggoClient` maps DTO ↔ domain at its boundary; nothing above the client
// sees these types.

// MARK: - Time scalar
//
// Traggo's GraphQL `Time` scalar is marshalled as RFC3339 (no fractional
// seconds, with a timezone offset) — see traggo/model/time.go. We wrap `Date`
// so it encodes/decodes to exactly that string wherever it appears in a
// request variable or response.
struct TraggoTime: Codable, Equatable, Hashable {
    var date: Date

    init(_ date: Date) { self.date = date }

    // We format with the *current* timezone so timespans line up with how the
    // web UI records them (day boundaries, stats, etc.).
    private static let output: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    // Parse leniently: with and without fractional seconds, any offset.
    private static let parsers: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        for parser in TraggoTime.parsers {
            if let parsed = parser.date(from: raw) {
                date = parsed
                return
            }
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Not an RFC3339 time: \(raw)"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(TraggoTime.output.string(from: date))
    }
}

// MARK: - API types (mirror schema.graphql)

struct Login: Decodable {
    let token: String
    let user: User
}

struct TagDefinition: Decodable, Hashable {
    let key: String
    let color: String

    var domain: LabelDefinition { LabelDefinition(key: key, color: color) }
}

/// A key/value pair attached to a timespan. This is the *wire* shape for both
/// `TimeSpanTag` (output) and `InputTimeSpanTag` (input) — no extra fields, so
/// it round-trips through GraphQL cleanly.
struct TimeSpanTag: Codable, Hashable {
    let key: String
    let value: String

    init(_ label: SpanLabel) {
        key = label.key
        value = label.value
    }

    var domain: SpanLabel { SpanLabel(key: key, value: value) }
}

struct TraggoTimeSpan: Decodable {
    let id: Int
    let start: TraggoTime
    let end: TraggoTime?      // nil == currently running
    let note: String
    let tags: [TimeSpanTag]?

    var domain: TimeSpan {
        TimeSpan(id: id, start: start.date, end: end?.date, note: note,
                 labels: (tags ?? []).map(\.domain))
    }
}

/// Pagination cursor for `timeSpans`. `startId` pins the page walk to the
/// newest id at the time of the first request so pages stay stable while new
/// spans are created; `offset` advances through the result set.
struct Cursor: Codable, Equatable {
    let hasMore: Bool
    let offset: Int
    let startId: Int
    let pageSize: Int

    /// The opaque token handed up through the protocol: the cursor,
    /// JSON-encoded, so traggo's paging state survives the round trip without
    /// its shape leaking upward. Nil once the server says there's no more.
    var pageToken: PageToken? {
        guard hasMore,
              let data = try? JSONEncoder().encode(self),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        return PageToken(rawValue: raw)
    }

    /// Nil for tokens this backend didn't mint — callers only ever hand back
    /// our own, so in practice this never fails.
    init?(_ token: PageToken) {
        guard let data = token.rawValue.data(using: .utf8),
              let cursor = try? JSONDecoder().decode(Cursor.self, from: data) else { return nil }
        self = cursor
    }
}

struct PagedTimeSpans: Decodable {
    let timeSpans: [TraggoTimeSpan]
    let cursor: Cursor
}
