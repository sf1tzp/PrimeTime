import ArgumentParser
import Foundation
import MomentTallyCore

// MARK: - moment-tally export

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Write the store as JSON to stdout.",
        discussion: """
            The same schema-versioned document as the app's Settings export
            (deterministic key order, pretty-printed, span ids included), so
            it pipes: `moment-tally export > backup.json`, `moment-tally export | jq`.

            --from/--to bound the export to local days (inclusive); a span
            counts when it overlaps the range, so one crossing midnight into
            the range is kept, and a running span never ends before it.
            --include/--exclude take label selectors — `key:value`, or a bare
            `key` for "has any label with this key". Every --include must
            match; any matching --exclude drops the span. A filtered document
            records its filter, so a partial export can't masquerade as a
            full backup.
            """)

    @Option(help: ArgumentHelp("First local day to export (inclusive).",
                               valueName: "YYYY-MM-DD"))
    var from: String?

    @Option(help: ArgumentHelp("Last local day to export (inclusive).",
                               valueName: "YYYY-MM-DD"))
    var to: String?

    @Option(help: ArgumentHelp("Keep only spans matching every selector; repeatable.",
                               valueName: "key[:value]"))
    var include: [String] = []

    @Option(help: ArgumentHelp("Drop spans matching any selector; repeatable.",
                               valueName: "key[:value]"))
    var exclude: [String] = []

    @OptionGroup var store: StoreOptions

    func run() async throws {
        try await mappingErrors {
            let filter = try ExportFilter(fromDay: from, toDay: to,
                                          include: include, exclude: exclude)
            let backend = try store.open()
            let document = try backend.exportData()
            let filtered = document.filtered(filter)
            let data = try LocalExport.encoder().encode(filtered)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            if filter.isEmpty {
                log("Exported \(filtered.timeSpans.count) timespans.")
            } else {
                log("Exported \(filtered.timeSpans.count) of \(document.timeSpans.count) timespans (filtered).")
            }
        }
    }
}
