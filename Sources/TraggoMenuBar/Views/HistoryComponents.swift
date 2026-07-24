import SwiftUI

// Shared pieces for the three history tabs (Log, Calendar, History/charts).

// MARK: - Week navigator

/// `‹ Today ›  Jan 26 – Feb 1, 2026` — drives `HistoryModel.weekStart`, shown
/// at the top of every history tab so they all stay on the same week.
struct WeekNavigatorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let history = model.history
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button { history.goToPreviousWeek() } label: {
                    Image(systemName: "chevron.left")
                }
                Button("Today") { history.goToToday() }
                    .disabled(history.isCurrentWeek)
                Button { history.goToNextWeek() } label: {
                    Image(systemName: "chevron.right")
                }
            }

            Text(history.weekLabel)
                .font(.headline)

            Spacer()

            if history.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await history.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Timespan editor

/// Inline editor for one timespan: start/end, tags, note, delete. Used
/// expanded-in-place by the Log and inside a popover by the Calendar.
struct TimeSpanEditorView: View {
    @Environment(AppModel.self) private var model
    let span: TimeSpan
    var onDone: () -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var tagRows: [TagRow]
    @State private var note: String
    @State private var isSaving = false
    @State private var confirmingDelete = false

    init(span: TimeSpan, onDone: @escaping () -> Void) {
        self.span = span
        self.onDone = onDone
        _start = State(initialValue: span.start.date)
        _end = State(initialValue: span.end?.date ?? Date())
        _tagRows = State(initialValue: (span.tags ?? []).map {
            TagRow(key: $0.key, value: $0.value)
        })
        _note = State(initialValue: span.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DatePicker("Start", selection: $start,
                           displayedComponents: [.date, .hourAndMinute])
                if span.isRunning {
                    // Stopping belongs to the popover's Stop button; here a
                    // running span just keeps running.
                    Label("Running", systemImage: "record.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    DatePicker("End", selection: $end,
                               displayedComponents: [.date, .hourAndMinute])
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach($tagRows) { $tag in
                    HStack {
                        TextField("key", text: $tag.key)
                            .autocorrectionDisabled()
                            .frame(width: 90)
                        Text(":").foregroundStyle(.secondary)
                        TextField("value", text: $tag.value)
                        Button(role: .destructive) {
                            tagRows.removeAll { $0.id == tag.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    tagRows.append(TagRow())
                } label: {
                    Label("Add tag", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
            .textFieldStyle(.roundedBorder)

            TextField("Note", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Delete", role: .destructive) {
                    confirmingDelete = true
                }
                .confirmationDialog("Delete this timespan?",
                                    isPresented: $confirmingDelete) {
                    Button("Delete", role: .destructive) {
                        Task {
                            isSaving = true
                            await model.history.delete(id: span.id)
                            isSaving = false
                            onDone()
                        }
                    }
                }
                Spacer()
                Button("Cancel") { onDone() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(isSaving)
        }
        .padding(10)
    }

    private func save() {
        Task {
            isSaving = true
            let saved = await model.history.update(
                id: span.id,
                start: start,
                end: span.isRunning ? nil : end,
                tags: tagRows.wireTags,
                note: note)
            isSaving = false
            if saved { onDone() }
        }
    }
}

// MARK: - Small formatting helpers

extension TimeSpan {
    /// "10:32 – 11:25", or "10:32 –" while running.
    var timeRangeLabel: String {
        let f = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
        let startText = start.date.formatted(f)
        guard let end else { return "\(startText) –" }
        return "\(startText) – \(end.date.formatted(f))"
    }

    /// Duration so far (running spans count up to now).
    var durationSeconds: TimeInterval {
        (end?.date ?? Date()).timeIntervalSince(start.date)
    }
}
