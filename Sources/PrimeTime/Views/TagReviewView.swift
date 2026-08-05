import SwiftUI
import PrimeTimeCore
import CoreTransferable
import UniformTypeIdentifiers

/// Drag payload: a value being dragged onto another key row — every instance
/// (`spanIDs` nil) or a hand-picked subset. JSON-encoded; the drag never
/// leaves the app.
private struct TagMovePayload: Codable, Transferable {
    let key: String
    let value: String
    let spanIDs: [Int]?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// The Tag Review tab: every tag key with the cardinality of its values —
/// distinct-value counts surface the messy keys (typos, near-duplicates,
/// casing drift) that quietly fragment the charts. Values expand into their
/// instances; renames are staged from the pencil, and dragging a value (or a
/// shift-click selection of instances) onto another key stages a move. Staged
/// changes collect in the Approve Changes pane at the bottom as a red/green
/// diff and apply as one batch.
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
    /// Selected instance rows (span ids), so a shift-click selection can drag
    /// as one payload.
    @State private var selectedSpans = Set<Int>()

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

            Divider()
            approvePane
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
                ForEach(TrailingRange.allCases) { range in
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
        List(selection: $selectedSpans) {
            ForEach(model.review.keyStats) { stat in
                DisclosureGroup {
                    ForEach(stat.values) { value in
                        valueGroup(key: stat.key, value: value)
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
            .buttonStyle(HoverIconButtonStyle())
            .help("Rename this key everywhere")
        }
        // Key rows accept dragged values/instances: dropping stages a move
        // under this key, with the value spelling editable while staged.
        .dropDestination(for: TagMovePayload.self) { items, _ in
            var accepted = false
            for item in items {
                // Whole-value drop on its own key is a no-op (use the pencil
                // to respell); a subset drop on its own key stages a
                // subset-only respell, which is meaningful.
                guard item.key != stat.key || item.spanIDs != nil else { continue }
                model.review.stage(StagedChange(
                    fromKey: item.key, fromValue: item.value,
                    toKey: stat.key, toValue: item.value,
                    spanIDs: item.spanIDs))
                accepted = true
            }
            if accepted { selectedSpans.removeAll() }
            return accepted
        }
    }

    /// One value row, expandable into its matched instances.
    private func valueGroup(key: String, value: ValueStat) -> some View {
        DisclosureGroup {
            let instances = model.review.matches(key: key, value: value.value)
                .sorted { $0.start > $1.start }
            ForEach(instances) { span in
                if span.isRunning {
                    // Running spans can't be staged (see movableMatches);
                    // their rows are inert — no selection, no drag.
                    instanceRow(span)
                        .help("Still running — stop it before moving it")
                } else {
                    instanceRow(span)
                        .tag(span.id)
                        .draggable(instancePayload(key: key, value: value.value, span: span)) {
                            TagPill(key: key, value: value.value,
                                    color: model.tagColor(for: key, value: value.value))
                        }
                }
            }
        } label: {
            valueRow(key: key, value: value)
                .draggable(TagMovePayload(key: key, value: value.value, spanIDs: nil)) {
                    TagPill(key: key, value: value.value,
                            color: model.tagColor(for: key, value: value.value))
                }
        }
        .padding(.leading, 17)   // align under the key name, past the swatch
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
            .buttonStyle(HoverIconButtonStyle())
            .help("Rename this value everywhere")
        }
    }

    /// One matched timespan under a value: date, duration, note. Selectable
    /// (shift-click for ranges) and draggable — dragging a selected row drags
    /// the whole selection.
    private func instanceRow(_ span: TimeSpan) -> some View {
        HStack(spacing: 8) {
            Text(span.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .monospacedDigit()
            Text(span.isRunning ? "running" : formatDuration(span.durationSeconds))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if !span.note.isEmpty {
                Text(span.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 17)
    }

    /// Dragging a row that's part of the current selection carries the whole
    /// selection (restricted to this value's movable instances); otherwise
    /// just the row itself.
    private func instancePayload(key: String, value: String, span: TimeSpan) -> TagMovePayload {
        let instanceIDs = Set(model.review.movableMatches(key: key, value: value).map(\.id))
        let selected = selectedSpans.intersection(instanceIDs)
        let ids = selected.contains(span.id) ? selected.sorted() : [span.id]
        return TagMovePayload(key: key, value: value, spanIDs: ids)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tag.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(model.review.isScanning
                 ? "Scanning…" : "No labels in the scanned range")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Approve Changes pane

    /// Reserved space at the bottom: a slim hint bar when nothing is staged,
    /// otherwise the git-style diff of pending changes with Approve/Cancel.
    private var approvePane: some View {
        @Bindable var review = model.review
        return Group {
            if review.staged.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                    Text("Nothing staged — drag a value (or selected instances) onto another key, or stage a rename from a pencil.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach($review.staged) { $change in
                                stagedChangeRow($change)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 150)

                    if review.isApplying {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(review.renameDone),
                                         total: Double(max(1, review.renameTotal)))
                            Text("change \(review.applyIndex + 1) of \(review.staged.count)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .fixedSize()
                            Button("Cancel") { review.cancelApply() }
                        }
                    } else {
                        HStack {
                            Text("\(review.staged.count) staged \(review.staged.count == 1 ? "change" : "changes")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Approve Changes") {
                                Task { await review.applyStaged() }
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    /// One staged change as prose — the old name highlighted red, the new
    /// green — e.g. "Move 3 'planning' spans from project to repo". The
    /// target value stays editable until approved.
    private func stagedChangeRow(_ change: Binding<StagedChange>) -> some View {
        let value = change.wrappedValue
        let count = model.review.spans(for: value).count
        let total = model.review.movableMatches(key: value.fromKey,
                                                value: value.fromValue).count
        let countText = value.spanIDs == nil ? "\(count)" : "\(count) of \(total)"
        return HStack(spacing: 6) {
            prose(for: value, count: countText)
                .lineLimit(1)
            if value.toValue != nil {
                TextField("value", text: Binding(
                    get: { change.wrappedValue.toValue ?? "" },
                    set: { change.wrappedValue.toValue = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .disabled(model.review.isApplying)
            }
            Spacer()
            Button {
                model.review.discard(value.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(HoverIconButtonStyle())
            .disabled(model.review.isApplying)
            .help("Discard this change")
        }
        .font(.callout)
        .padding(.horizontal, 4)
    }

    /// The sentence describing a staged change, ending just before the
    /// editable value field (when the change carries one).
    private func prose(for change: StagedChange, count: String) -> Text {
        let toKey = normalizeKey(change.toKey)
        let fromValue = (change.fromValue?.isEmpty == true)
            ? "(no value)" : change.fromValue ?? ""
        if change.fromValue == nil {
            // Key rename: values ride along, so no value field follows.
            return Text("Rename key ")
                + Text(change.fromKey).bold().foregroundColor(.red)
                + Text(" to ")
                + Text(toKey).bold().foregroundColor(.green)
                + Text(" (\(count) spans)").foregroundColor(.secondary)
        }
        if toKey == change.fromKey {
            return Text("Rename \(count) ")
                + Text("'\(change.fromKey): \(fromValue)'").bold().foregroundColor(.red)
                + Text(" spans to ")
                + Text("'\(toKey):").bold().foregroundColor(.green)
        }
        return Text("Move \(count) ")
            + Text("'\(fromValue)'").bold().foregroundColor(.red)
            + Text(" spans from ")
            + Text(change.fromKey).bold().foregroundColor(.red)
            + Text(" to ")
            + Text(toKey).bold().foregroundColor(.green)
    }
}

/// Staging sheet for a rename: shows the blast radius, then adds the change
/// to the Approve Changes pane rather than touching the server directly.
private struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    let key: String
    let value: String?    // nil = renaming the key itself
    var onDone: () -> Void

    @State private var newSpelling: String

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
        // Running spans are excluded — staged rewrites only touch finished ones.
        let count = review.movableMatches(key: key, value: value).count
        VStack(alignment: .leading, spacing: 12) {
            Text(isKeyRename
                 ? "Rename label key “\(key)”"
                 : "Rename a value of “\(key)”")
                .font(.headline)

            TextField(isKeyRename ? "New key" : "New value", text: $newSpelling)
                .textFieldStyle(.roundedBorder)

            Text(isKeyRename
                 ? "Stages a rewrite of \(count) scanned \(count == 1 ? "timespan" : "timespans") to “\(normalizeKey(newSpelling))”, carrying the colour over. Applied from the Approve Changes pane; spans outside the scanned range keep the old key."
                 : "Stages a rewrite of \(count) scanned \(count == 1 ? "timespan" : "timespans") carrying “\(key): \(value ?? "")”. Applied from the Approve Changes pane; spans outside the scanned range keep the old value.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button("Stage") { stage() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(invalid || count == 0)
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private func stage() {
        let to = newSpelling.trimmingCharacters(in: .whitespaces)
        if let value {
            model.review.stage(StagedChange(
                fromKey: key, fromValue: value,
                toKey: key, toValue: to, spanIDs: nil))
        } else {
            model.review.stage(StagedChange(
                fromKey: key, fromValue: nil,
                toKey: to, toValue: nil, spanIDs: nil))
        }
        onDone()
    }
}
