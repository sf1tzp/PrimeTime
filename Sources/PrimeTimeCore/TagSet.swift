import Foundation

/// One editable tag inside a tag set. It carries a stable `id` so SwiftUI list
/// editing keeps field focus as you type — but that `id` is local only and
/// never persisted to the backend (we convert to `SpanLabel` at the boundary).
package struct TagRow: Identifiable, Codable, Hashable {
    package var id = UUID()
    package var key: String = ""
    package var value: String = ""

    package init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// A named bundle of tags the user can start with one click — "label set" in
/// UI copy (the type name predates the tag→label rename, #27). Persisted in
/// the local database and carried by sync (#92), so a user's sets follow
/// their account across connected Macs.
package struct TagSet: Identifiable, Codable, Hashable {
    package var id = UUID()
    package var name: String = ""
    package var tags: [TagRow] = []
    /// SF Symbol shown on the set's launcher card. Optional so sets saved
    /// before icons existed keep decoding; `symbol` supplies the default.
    package var symbolName: String?
    /// "#rrggbb" fallback colour for the set's launcher card, used only when
    /// the set has no labels to borrow a colour from (a quick-labels-only
    /// set). Local-only — not part of the sync payload. Optional so older
    /// saves keep decoding; nil means the accent colour.
    package var colorHex: String?

    package init(id: UUID = UUID(), name: String = "", tags: [TagRow] = [],
                 symbolName: String? = nil, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.tags = tags
        self.symbolName = symbolName
        self.colorHex = colorHex
    }

    /// The symbol to render for this set.
    package var symbol: String { symbolName ?? "tag" }

    /// The domain form for starting a timespan. Traggo lower-cases tag keys
    /// and forbids spaces, so we normalise here to match how definitions are
    /// stored.
    package var labels: [SpanLabel] { tags.labels }

    /// The labels to start when a quick label rides along: the set's tags plus
    /// the quick label — *replacing* the set's value for the same key, because
    /// a quick label hones a set (`type: review` over the set's baked-in
    /// `type: programming`) rather than double-labelling it.
    package func labels(applying quick: TagRow) -> [SpanLabel] {
        let key = normalizeKey(quick.key)
        return (tags.filter { normalizeKey($0.key) != key } + [quick]).labels
    }
}

/// Traggo tag keys must be lower-case with no spaces. Surrounding whitespace
/// is a typo, not intent, so it's trimmed rather than turned into dashes.
package func normalizeKey(_ key: String) -> String {
    key.trimmingCharacters(in: .whitespaces)
        .lowercased().replacingOccurrences(of: " ", with: "-")
}

/// The composite dictionary key for per-`key: value` colour overrides — a unit
/// separator rather than ":" because tag values may themselves contain ":".
/// Shared between `AppModel` (which keys its in-memory dictionary this way,
/// and the legacy UserDefaults store with it) and `LocalBackend` (which splits
/// the composite back into real columns).
package enum ValueColorKey {
    package static let separator: Character = "\u{1F}"

    package static func join(_ key: String, _ value: String) -> String {
        "\(key)\(separator)\(value)"
    }

    package static func split(_ raw: String) -> (key: String, value: String)? {
        guard let index = raw.firstIndex(of: separator) else { return nil }
        return (String(raw[..<index]), String(raw[raw.index(after: index)...]))
    }
}

package extension [TagRow] {
    /// Drop empty rows, normalise keys, and trim values — the domain form for
    /// any mutation. Editors bind their fields to the raw rows (trimming per
    /// keystroke would forbid typing internal spaces), so surrounding
    /// whitespace is shed here, at the storage boundary.
    var labels: [SpanLabel] {
        filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { SpanLabel(key: normalizeKey($0.key),
                             value: $0.value.trimmingCharacters(in: .whitespaces)) }
    }
}
