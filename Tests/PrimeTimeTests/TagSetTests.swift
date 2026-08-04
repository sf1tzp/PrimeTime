import Foundation
import Testing
@testable import PrimeTimeCore

/// Tag input normalisation: whatever the editors let you type, the labels
/// that reach a mutation carry no surrounding whitespace in key or value.
@Suite struct TagSetTests {

    @Test func normalizeKeyLowercasesAndDashes() {
        #expect(normalizeKey("My Key") == "my-key")
    }

    @Test func decodesSavesThatPredateCardColor() throws {
        // Sets persisted before `colorHex` existed (the legacy UserDefaults
        // JSON the v1 import reads) must keep decoding, colourless.
        let json = """
        {"id":"6F1D2C3B-0000-0000-0000-000000000000","name":"Gaming",
         "tags":[{"id":"6F1D2C3B-0000-0000-0000-000000000001","key":"","value":""}]}
        """
        let set = try JSONDecoder().decode(TagSet.self, from: Data(json.utf8))
        #expect(set.name == "Gaming")
        #expect(set.colorHex == nil)
    }

    @Test func normalizeKeyTrimsBeforeDashing() {
        // Surrounding whitespace is a typo, not intent — " repo " must not
        // become "-repo-".
        #expect(normalizeKey(" repo ") == "repo")
        #expect(normalizeKey("  My Key ") == "my-key")
    }

    @Test func labelsTrimValues() {
        let rows = [TagRow(key: "repo", value: " foo "),
                    TagRow(key: " client ", value: "acme corp")]
        #expect(rows.labels == [SpanLabel(key: "repo", value: "foo"),
                                SpanLabel(key: "client", value: "acme corp")])
    }

    @Test func labelsDropKeylessRows() {
        let rows = [TagRow(key: "  ", value: "orphan"),
                    TagRow(key: "a", value: "b")]
        #expect(rows.labels == [SpanLabel(key: "a", value: "b")])
    }

    // MARK: Quick labels (labels(applying:))

    @Test func applyingQuickLabelAppends() {
        let set = TagSet(tags: [TagRow(key: "repo", value: "a"),
                                TagRow(key: "feat", value: "b")])
        #expect(set.labels(applying: TagRow(key: "type", value: "coding"))
                == [SpanLabel(key: "repo", value: "a"),
                    SpanLabel(key: "feat", value: "b"),
                    SpanLabel(key: "type", value: "coding")])
    }

    @Test func applyingQuickLabelReplacesSameKey() {
        // A quick label hones the set, so its value wins over the set's
        // baked-in value for the same key — no double `type:`.
        let set = TagSet(tags: [TagRow(key: "repo", value: "a"),
                                TagRow(key: "type", value: "programming")])
        #expect(set.labels(applying: TagRow(key: "type", value: "review"))
                == [SpanLabel(key: "repo", value: "a"),
                    SpanLabel(key: "type", value: "review")])
    }

    @Test func applyingQuickLabelMatchesNormalisedKeys() {
        // "Type " and "type" are the same key once normalised.
        let set = TagSet(tags: [TagRow(key: "Type ", value: "programming")])
        #expect(set.labels(applying: TagRow(key: "type", value: "review"))
                == [SpanLabel(key: "type", value: "review")])
    }
}
