import SwiftUI
import PrimeTimeCore

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
///
/// Two regimes: a *finished* span edits view-local drafts, saved through
/// `HistoryModel.update`. A *running* span instead binds the shared
/// `SpanEditSession` — the same drafts the popover's pencil editor shows —
/// so the running timer has one edit, whichever surface it's typed into
/// (#61). Explicit Save for now; whether the running editor should
/// live-commit like the popover is a review decision.
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
        _start = State(initialValue: span.start)
        _end = State(initialValue: span.end ?? Date())
        _tagRows = State(initialValue: span.labels.map {
            TagRow(key: $0.key, value: $0.value)
        })
        _note = State(initialValue: span.note)
    }

    var body: some View {
        if span.isRunning {
            runningBody
        } else {
            finishedBody
        }
    }

    // MARK: Running span — the shared session

    @ViewBuilder
    private var runningBody: some View {
        if let session = model.editSession, session.spanID == span.id {
            RunningSessionEditor(session: session, onDone: onDone)
        } else {
            // The session ended or moved to another editor — collapse.
            // Claiming it is the expansion click's job (see LogView /
            // CalendarView), never a render side effect: a row whose view
            // identity gets recreated while expanded (a filter toggle, lazy
            // scrolling) must not steal the session back from whichever
            // surface holds it now.
            Color.clear.frame(height: 1)
                .task { onDone() }
        }
    }

    // MARK: Finished span — view-local drafts

    private var finishedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MinuteSteppingDatePicker(label: "Start", date: $start)
                MinuteSteppingDatePicker(label: "End", date: $end)
            }

            LabelRowsEditor(rows: $tagRows)
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
                end: end,
                tags: tagRows.labels,
                note: note)
            isSaving = false
            if saved { onDone() }
        }
    }
}

/// The running-span editor body: the same chrome as the finished editor, but
/// every field is a binding into the shared `SpanEditSession`, and Save goes
/// through the model's one commit funnel.
private struct RunningSessionEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: SpanEditSession
    var onDone: () -> Void

    @State private var isSaving = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MinuteSteppingDatePicker(label: "Start", date: $session.startDraft)
                // Stopping belongs to the popover's Stop button; here a
                // running span just keeps running.
                Label("Running", systemImage: "record.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            LabelRowsEditor(rows: $session.tagDrafts)
                .textFieldStyle(.roundedBorder)

            TextField("Note", text: $session.noteDraft)
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
                            await model.history.delete(id: session.spanID)
                            isSaving = false
                            onDone()
                        }
                    }
                }
                Spacer()
                Button("Cancel") {
                    model.cancelEditing()
                    onDone()
                }
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
            await model.finishEditing()
            isSaving = false
            // A failed write keeps the session (and this editor) open.
            if model.editSession == nil { onDone() }
        }
    }
}

/// The label rows shared by both editor regimes: one row per tag (colour
/// swatch, key, value, remove) plus the add-label button.
private struct LabelRowsEditor: View {
    @Binding var rows: [TagRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($rows) { $tag in
                HStack(spacing: 6) {
                    TagColorPicker(key: tag.key, value: tag.value)
                    TextField("key", text: $tag.key)
                        .autocorrectionDisabled()
                        .frame(width: LabelEditorStyle.keyFieldWidth)
                    Text(":").foregroundStyle(.secondary)
                    TextField("value", text: $tag.value)
                        .autocorrectionDisabled()
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == tag.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                rows.append(TagRow())
            } label: {
                Label("Add Label", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}

/// A date+time field whose up/down buttons step by the minute. The stock
/// `.stepperField` picker sends the arrows to whichever element is selected —
/// the *year*, before anything is clicked — so use the stepper-less `.field`
/// style and supply our own minute stepper. Arrow keys inside the field still
/// adjust the clicked element as usual.
private struct MinuteSteppingDatePicker: View {
    let label: String
    @Binding var date: Date

    var body: some View {
        HStack(spacing: 2) {
            DatePicker(label, selection: $date,
                       displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
            Stepper(label) {
                step(by: 1)
            } onDecrement: {
                step(by: -1)
            }
            .labelsHidden()
        }
    }

    /// Calendar arithmetic rather than ±60s so steps stay wall-clock minutes
    /// across DST transitions.
    private func step(by minutes: Int) {
        if let stepped = Calendar.current.date(byAdding: .minute,
                                               value: minutes, to: date) {
            date = stepped
        }
    }
}

// MARK: - Small formatting helpers

extension TimeSpan {
    /// "10:32 – 11:25", or "10:32 –" while running.
    var timeRangeLabel: String {
        let f = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
        let startText = start.formatted(f)
        guard let end else { return "\(startText) –" }
        return "\(startText) – \(end.formatted(f))"
    }

    /// Duration so far (running spans count up to now).
    var durationSeconds: TimeInterval {
        (end ?? Date()).timeIntervalSince(start)
    }
}
