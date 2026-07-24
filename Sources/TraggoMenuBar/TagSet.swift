import Foundation

/// One editable tag inside a tag set. It carries a stable `id` so SwiftUI list
/// editing keeps field focus as you type — but that `id` is local only and
/// never sent to the server (we convert to `TimeSpanTag` on the wire).
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

    /// The wire form for `createTimeSpan`. Traggo lower-cases tag keys and
    /// forbids spaces, so we normalise here to match how definitions are stored.
    var wireTags: [TimeSpanTag] {
        tags
            .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { TimeSpanTag(key: normalizeKey($0.key), value: $0.value) }
    }

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
