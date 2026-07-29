import SwiftUI

/// The Tag Review tab: every tag key with the cardinality of its values —
/// distinct-value counts surface the messy keys (typos, near-duplicates,
/// casing drift) that quietly fragment the charts. Each key expands to its
/// values with usage counts, and both keys and values can be renamed, which
/// rewrites the affected timespans.
struct TagReviewView: View {
    @Environment(AppModel.self) private var model

    /// What the rename sheet is renaming: a value of a key, or (value == nil)
    /// the key itself.
    private struct RenameTarget: Identifiable {
        let key: String
        let value: String?
        var id: String { value.map { "\(key)\u{1F}\($0)" } ?? key }
    }

    @State private var renameTarget: RenameTarget?

    var body: some View {
        let review = model.review
        VStack(spacing: 0) {
            controls
            Divider()

            if let error = review.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(6)
            }

            if review.keyStats.isEmpty {
                emptyState
            } else {
                statsList
            }
        }
        .task {
            if !review.hasScanned { await review.scan() }
        }
        .sheet(item: $renameTarget) { target in
            RenameSheet(key: target.key, value: target.value) {
                renameTarget = nil
            }
            .environment(model)
        }
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var review = model.review
        return HStack(spacing: 8) {
            Picker("Range", selection: $review.range) {
                ForEach(ScanRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .fixedSize()
            .onChange(of: review.range) {
                Task { await review.scan() }
            }

            Button {
                Task { await review.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan")
            .disabled(review.isScanning)

            if review.isScanning {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Text("\(review.keyStats.count) keys · \(review.scannedCount) timespans")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Stats list

    private var statsList: some View {
        List {
            ForEach(model.review.keyStats) { stat in
                DisclosureGroup {
                    ForEach(stat.values) { value in
                        valueRow(key: stat.key, value: value)
                    }
                } label: {
                    keyRow(stat)
                }
            }
        }
        .listStyle(.inset)
    }

    private func keyRow(_ stat: KeyStat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.tagColor(for: stat.key))
                .frame(width: 9, height: 9)
            Text(stat.key)
                .fontWeight(.medium)
            Text("\(stat.values.count) \(stat.values.count == 1 ? "value" : "values")")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            Spacer()
            Text("\(stat.spanCount)×")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(formatDuration(stat.seconds))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Button {
                renameTarget = RenameTarget(key: stat.key, value: nil)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Rename this key everywhere")
        }
    }

    private func valueRow(key: String, value: ValueStat) -> some View {
        HStack(spacing: 8) {
            Text(value.value.isEmpty ? "(no value)" : value.value)
                .foregroundStyle(value.value.isEmpty ? .secondary : .primary)
            Spacer()
            Text("\(value.count)×")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(formatDuration(value.seconds))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
            Button {
                renameTarget = RenameTarget(key: key, value: value.value)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Rename this value everywhere")
        }
        .padding(.leading, 17)   // align under the key name, past the swatch
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tag.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(model.review.isScanning
                 ? "Scanning…" : "No tags in the scanned range")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Confirm-and-run sheet for a rename: shows the blast radius, then drives
/// the per-timespan rewrite with progress and cancellation. Kept open when
/// spans fail so the count is visible — re-running converges.
private struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    let key: String
    let value: String?    // nil = renaming the key itself
    var onDone: () -> Void

    @State private var newSpelling: String
    @State private var didRun = false

    init(key: String, value: String?, onDone: @escaping () -> Void) {
        self.key = key
        self.value = value
        self.onDone = onDone
        _newSpelling = State(initialValue: value ?? key)
    }

    private var isKeyRename: Bool { value == nil }

    private var invalid: Bool {
        let trimmed = newSpelling.trimmingCharacters(in: .whitespaces)
        if isKeyRename { return normalizeKey(trimmed).isEmpty || normalizeKey(trimmed) == key }
        return trimmed == value
    }

    var body: some View {
        let review = model.review
        let count = review.matches(key: key, value: value).count
        VStack(alignment: .leading, spacing: 12) {
            Text(isKeyRename
                 ? "Rename tag key “\(key)”"
                 : "Rename a value of “\(key)”")
                .font(.headline)

            TextField(isKeyRename ? "New key" : "New value", text: $newSpelling)
                .textFieldStyle(.roundedBorder)

            Text(isKeyRename
                 ? "Rewrites \(count) scanned \(count == 1 ? "timespan" : "timespans") to “\(normalizeKey(newSpelling))” and carries the colour over. Spans outside the scanned range keep the old key."
                 : "Rewrites \(count) scanned \(count == 1 ? "timespan" : "timespans") carrying “\(key): \(value ?? "")”. Spans outside the scanned range keep the old value.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if review.isRenaming {
                ProgressView(value: Double(review.renameDone),
                             total: Double(max(1, review.renameTotal)))
                HStack {
                    Text("\(review.renameDone) / \(review.renameTotal)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { review.cancelRename() }
                }
            } else {
                HStack {
                    if didRun, review.renameFailures > 0 {
                        Text("\(review.renameFailures) failed — rename again to retry")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Cancel") { onDone() }
                    Button("Rename") { run() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(invalid || count == 0)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private func run() {
        let review = model.review
        let to = newSpelling.trimmingCharacters(in: .whitespaces)
        didRun = true
        Task {
            if let value {
                await review.renameValue(key: key, from: value, to: to)
            } else {
                await review.renameKey(from: key, to: to)
            }
            if review.renameFailures == 0 {
                onDone()
            }
        }
    }
}
