import Foundation

/// One editable tag inside a tag set. It carries a stable `id` so SwiftUI list
/// editing keeps field focus as you type — but that `id` is local only and
/// never persisted to the backend (we convert to `SpanLabel` at the boundary).
struct TagRow: Identifiable, Codable, Hashable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

/// A named bundle of tags the user can start with one click. "Tag set" is our
/// term for a reusable group of tags — e.g. "Project A" → `proj:a`. Persisted
/// locally (UserDefaults); tag sets are a client-side convenience, not a server
/// concept. Tag *colours*, by contrast, live on the server keyed by tag key.
struct TagSet: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var tags: [TagRow] = []
    /// SF Symbol shown on the set's launcher card. Optional so sets saved
    /// before icons existed keep decoding; `symbol` supplies the default.
    var symbolName: String?

    /// The symbol to render for this set.
    var symbol: String { symbolName ?? "tag" }

    /// The domain form for starting a timespan. Traggo lower-cases tag keys
    /// and forbids spaces, so we normalise here to match how definitions are
    /// stored.
    var labels: [SpanLabel] { tags.labels }

    static let samples: [TagSet] = [
        TagSet(name: "Deep Work", tags: [TagRow(key: "type", value: "programming")]),
        TagSet(name: "Meeting", tags: [TagRow(key: "type", value: "meeting")]),
        TagSet(name: "Email", tags: [TagRow(key: "type", value: "email")]),
    ]
}

/// Traggo tag keys must be lower-case with no spaces.
func normalizeKey(_ key: String) -> String {
    key.lowercased().replacingOccurrences(of: " ", with: "-")
}

/// The composite dictionary key for per-`key: value` colour overrides — a unit
/// separator rather than ":" because tag values may themselves contain ":".
/// Shared between `AppModel` (which keys its in-memory dictionary this way,
/// and the legacy UserDefaults store with it) and `LocalBackend` (which splits
/// the composite back into real columns).
enum ValueColorKey {
    static let separator: Character = "\u{1F}"

    static func join(_ key: String, _ value: String) -> String {
        "\(key)\(separator)\(value)"
    }

    static func split(_ raw: String) -> (key: String, value: String)? {
        guard let index = raw.firstIndex(of: separator) else { return nil }
        return (String(raw[..<index]), String(raw[raw.index(after: index)...]))
    }
}

extension [TagRow] {
    /// Drop empty rows and normalise keys — the domain form for any mutation.
    var labels: [SpanLabel] {
        filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { SpanLabel(key: normalizeKey($0.key), value: $0.value) }
    }
}
