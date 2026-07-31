import Foundation
import Testing
@testable import PrimeTimeCore

/// Tag input normalisation: whatever the editors let you type, the labels
/// that reach a mutation carry no surrounding whitespace in key or value.
@Suite struct TagSetTests {

    @Test func normalizeKeyLowercasesAndDashes() {
        #expect(normalizeKey("My Key") == "my-key")
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
}
