import Foundation
import GRDB

// MARK: - Export document (#57)

/// The JSON snapshot of everything the local store owns: timespans with their
/// labels, label definitions, per-value colour overrides, and label sets with
/// their members. Schema-versioned so the format can evolve and a future
/// import can validate what it's reading; sync bookkeeping (dirty flags,
/// server mappings, tombstones) stays out — it describes a connection, not
/// the user's data.
struct LocalExport: Codable, Equatable {
    /// Bump when the document shape changes, so an import can tell exactly
    /// what it has been handed.
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var exportedAt: Date
    var timeSpans: [Span]
    var labelDefinitions: [LabelDefinition]
    var valueColors: [ValueColor]
    var labelSets: [LabelSet]

    /// One timespan with its labels inline, in display order. `id` is the
    /// local rowid — exported so spans can be cross-referenced, not promised
    /// stable across databases. A nil `end` is a still-running span.
    struct Span: Codable, Equatable {
        var id: Int64
        var start: Date
        var end: Date?
        var note: String
        var labels: [Label]
    }

    struct Label: Codable, Equatable {
        var key: String
        var value: String
    }

    struct ValueColor: Codable, Equatable {
        var key: String
        var value: String
        var color: String
    }

    /// A label set and its member labels. Array order carries the launcher
    /// and member positions, the way the UI shows them.
    struct LabelSet: Codable, Equatable {
        var id: String
        var name: String
        var symbol: String?
        var labels: [Label]
    }

    // MARK: Wire format

    /// Dates are ISO 8601 with the exporting machine's UTC offset and
    /// millisecond precision — unambiguous across timezones, and exactly the
    /// precision GRDB stores.
    static func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let formatter = dateFormatter()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    /// The import counterpart's decoder, here so tests prove the round trip
    /// the schema-versioned format is designed for.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = dateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = formatter.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an ISO 8601 date: \(raw)")
            }
            return date
        }
        return decoder
    }
}

// MARK: - LocalBackend surface

extension LocalBackend {
    /// Snapshot the whole store as an export document, in one read
    /// transaction so the result is a consistent point in time. Synchronous
    /// like the tag-set surface: Settings calls it from a button press and
    /// the store is a single local file.
    func exportData(at now: Date = Date()) throws -> LocalExport {
        try dbQueue.read { db in
            let spanRows = try TimeSpanRow
                .order(Column("start"), Column("id"))
                .fetchAll(db)
            let labelRows = try SpanLabelRow.order(Column("rowid")).fetchAll(db)
            let labelsBySpan = Dictionary(grouping: labelRows, by: \.spanId)
            let spans = spanRows.map { row in
                LocalExport.Span(
                    id: row.id!, start: row.start, end: row.end, note: row.note,
                    labels: (labelsBySpan[row.id!] ?? []).map {
                        LocalExport.Label(key: $0.key, value: $0.value)
                    })
            }

            let definitions = try LabelDefinition.order(Column("key")).fetchAll(db)

            let colors = try ValueColorRow
                .order(Column("key"), Column("value"))
                .fetchAll(db)
                .map { LocalExport.ValueColor(key: $0.key, value: $0.value, color: $0.color) }

            let setRows = try LabelSetRow.order(Column("position")).fetchAll(db)
            let memberRows = try LabelSetMemberRow.order(Column("position")).fetchAll(db)
            let membersBySet = Dictionary(grouping: memberRows, by: \.setId)
            let sets = setRows.map { row in
                LocalExport.LabelSet(
                    id: row.id, name: row.name, symbol: row.symbol,
                    labels: (membersBySet[row.id] ?? []).map {
                        LocalExport.Label(key: $0.key, value: $0.value)
                    })
            }

            return LocalExport(exportedAt: now, timeSpans: spans,
                               labelDefinitions: definitions,
                               valueColors: colors, labelSets: sets)
        }
    }

    /// `exportData` serialised for a save panel: pretty-printed JSON with
    /// deterministic key order.
    func exportJSON(at now: Date = Date()) throws -> Data {
        try LocalExport.encoder().encode(exportData(at: now))
    }
}
