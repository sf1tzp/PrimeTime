import SwiftUI

/// The Log tab: a day-sectioned, scrollable list of the week's timespans.
/// Clicking a row expands it into an inline `TimeSpanEditorView`.
struct LogView: View {
    @Environment(AppModel.self) private var model
    /// The id of the span currently expanded for editing (one at a time).
    @State private var editingID: Int?

    var body: some View {
        let history = model.history
        VStack(spacing: 0) {
            WeekNavigatorView()
            Divider()

            if let error = history.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            if history.spans.isEmpty && !history.isLoading {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0,
                               pinnedViews: .sectionHeaders) {
                        // Newest day first, matching the newest-first span order.
                        ForEach(daysWithSpans, id: \.day.start) { group in
                            Section {
                                ForEach(group.spans) { span in
                                    row(for: span)
                                    Divider().padding(.leading, 12)
                                }
                            } header: {
                                dayHeader(group.day)
                            }
                        }
                    }
                }
            }
        }
        .task { await history.loadIfNeeded() }
    }

    /// Days of the week that have at least one span starting in them, newest
    /// first, each with its spans (already sorted newest first).
    private var daysWithSpans: [(day: DateInterval, spans: [TimeSpan])] {
        model.history.days.reversed().compactMap { day in
            let spans = model.history.spans.filter { day.contains($0.start.date) }
            return spans.isEmpty ? nil : (day, spans)
        }
    }

    private func dayHeader(_ day: DateInterval) -> some View {
        HStack {
            Text(day.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(formatDuration(model.history.totalSeconds(in: day)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    @ViewBuilder
    private func row(for span: TimeSpan) -> some View {
        if editingID == span.id {
            TimeSpanEditorView(span: span) { editingID = nil }
                .background(Color.accentColor.opacity(0.06))
        } else {
            Button {
                editingID = span.id
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(span.timeRangeLabel)
                            .font(.callout.monospacedDigit())
                        Text(span.isRunning
                             ? "running"
                             : formatDuration(span.durationSeconds))
                            .font(.caption)
                            .foregroundStyle(span.isRunning ? .orange : .secondary)
                    }
                    .frame(width: 110, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        if let tags = span.tags, !tags.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(tags, id: \.self) { tag in
                                    TagPill(key: tag.key, value: tag.value,
                                            color: model.tagColor(for: tag.key, value: tag.value))
                                }
                            }
                        }
                        if !span.note.isEmpty {
                            Text(span.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to edit")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No timespans this week")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
