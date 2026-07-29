import SwiftUI
import AppKit

/// The contents of the menu-bar popover.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model

    /// Which running timespan is being edited in place (tags + note), plus
    /// local drafts. Seeded on entering edit mode so a background poll can't
    /// clobber edits; dropped if the timespan stops from elsewhere.
    @State private var editingTimerID: TimeSpan.ID?
    @State private var tagDrafts: [TagRow] = []
    @State private var noteDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isAuthenticated {
                authenticatedBody
            } else {
                LoginView()
            }
        }
        .padding(12)
        // Refresh whenever the popover opens so we reflect changes made in the
        // web UI without waiting for the 30s poll.
        .task {
            await model.refresh()
        }
        .onChange(of: model.activeTimers.map(\.id)) {
            // Drop the in-place editor if its timespan stopped elsewhere.
            if let id = editingTimerID,
               !model.activeTimers.contains(where: { $0.id == id }) {
                editingTimerID = nil
            }
        }
    }

    @ViewBuilder
    private var authenticatedBody: some View {
        activeTimerSection

        Divider()

        Text("Quick start")
            .font(.caption)
            .foregroundStyle(.secondary)

        if model.tagSets.isEmpty {
            Text("No tag sets yet — add some in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Sets whose tags are running right now are hidden (they reappear
            // on stop). The cap (0 = all) applies to what's left, so a hidden
            // set doesn't consume one of the N slots; the rest hide behind a
            // "more…" row so the popover stays glanceable.
            let candidates = model.tagSets.filter { !model.isRunning($0) }
            let limit = model.menuTagSetLimit
            let visibleSets = limit > 0 ? Array(candidates.prefix(limit)) : candidates
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visibleSets) { set in
                    quickStartRow(set)
                }
                if candidates.count > visibleSets.count {
                    // The launcher is the "see everything" surface.
                    Button {
                        openSettings(tab: .launcher)
                    } label: {
                        Text("\(candidates.count - visibleSets.count) more…")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(MenuRowButtonStyle())
                }
            }
        }

        if let error = model.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }

        Divider()

        // Full-width rows, like Rectangle's menu: quick access to the content
        // tabs of the settings window, then Settings and Quit.
        VStack(spacing: 2) {
            Button {
                openSettings(tab: .launcher)
            } label: {
                Label("Launcher", systemImage: "square.grid.2x2")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button {
                openSettings(tab: .log)
            } label: {
                Label("Log", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button {
                openSettings(tab: .calendar)
            } label: {
                Label("Calendar", systemImage: "calendar")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button {
                openSettings(tab: .history)
            } label: {
                Label("History", systemImage: "chart.pie")
            }
            .buttonStyle(MenuRowButtonStyle())

            Divider()

            Button {
                openSettings(tab: .settings)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(MenuRowButtonStyle())
        }
        .font(.callout)
    }

    private func openSettings(tab: SettingsTab) {
        SettingsWindowManager.shared.show(model: model, tab: tab)
    }

    /// One quick-start row. The row itself starts the set and stays greyed out
    /// while a timer runs (stop before starting); in that state a trailing ＋
    /// starts the set *alongside* the running timer instead.
    private func quickStartRow(_ set: TagSet) -> some View {
        HStack(spacing: 0) {
            Button {
                Task { await model.start(tagSet: set) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(set.name.isEmpty ? "Untitled" : set.name)
                    let tags = set.tags.filter { !$0.key.isEmpty }
                    if !tags.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(tags) { tag in
                                TagPill(key: tag.key, value: tag.value,
                                        color: model.tagColor(for: tag.key, value: tag.value))
                            }
                        }
                    }
                }
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(model.activeTimer != nil || model.isBusy)

            if model.activeTimer != nil {
                Button {
                    Task { await model.start(tagSet: set) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(HoverIconButtonStyle())
                .disabled(model.isBusy)
                .help("Start alongside the running timer")
            }
        }
    }

    @ViewBuilder
    private var activeTimerSection: some View {
        if !model.activeTimers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.activeTimers) { timer in
                    runningRow(timer)
                }
            }
        }

        // Ad-hoc start with no tags — capture time first, classify it in the
        // row editor while the clock runs. Available even while timers run:
        // the blank timespan starts alongside them.
        Button {
            Task {
                if let created = await model.start(tags: []) {
                    beginEditing(created)
                }
            }
        } label: {
            Label("Start blank timer", systemImage: "circle.dashed")
        }
        .buttonStyle(MenuRowButtonStyle())
        .disabled(model.isBusy)
    }

    /// One running timespan, uniform however many run: elapsed + tags, with
    /// edit (pencil) and stop (square) folded into the row. The pencil toggles
    /// an in-place editor for the row's tags and note.
    @ViewBuilder
    private func runningRow(_ timer: TimeSpan) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(model.elapsedString(since: timer.start.date))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
            let tags = timer.tags ?? []
            if tags.isEmpty {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        TagPill(key: tag.key, value: tag.value,
                                color: model.tagColor(for: tag.key, value: tag.value))
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                if editingTimerID == timer.id {
                    editingTimerID = nil
                } else {
                    beginEditing(timer)
                }
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(HoverIconButtonStyle())
            .help("Edit tags and note")
            Button {
                Task { await model.stop(id: timer.id) }
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(HoverIconButtonStyle())
            .disabled(model.isBusy)
            .help("Stop")
        }
        if editingTimerID == timer.id {
            timerEditor
        }
    }

    /// In-place editor for a running row — one line per tag (colour swatch,
    /// key, value, remove) plus the note, with Add / Cancel / Save. Save
    /// commits tags and note together via `updateRunning`.
    private var timerEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($tagDrafts) { $tag in
                HStack(spacing: 4) {
                    TagColorPicker(key: tag.key, value: tag.value)
                    TextField("key", text: $tag.key)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                    Text(":").foregroundStyle(.secondary)
                    TextField("value", text: $tag.value)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        tagDrafts.removeAll { $0.id == tag.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            TextField("Add a note…", text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveEdits() }
            HStack {
                Button {
                    tagDrafts.append(TagRow())
                } label: {
                    Label("Add tag", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { editingTimerID = nil }
                    .buttonStyle(.borderless)
                Button("Save") { saveEdits() }
                    .disabled(model.isBusy)
            }
        }
    }

    private func beginEditing(_ timer: TimeSpan) {
        let rows = (timer.tags ?? []).map { TagRow(key: $0.key, value: $0.value) }
        tagDrafts = rows.isEmpty ? [TagRow()] : rows  // an empty row, ready to type
        noteDraft = timer.note
        editingTimerID = timer.id
    }

    private func saveEdits() {
        guard let id = editingTimerID else { return }
        let wire = tagDrafts.wireTags
        Task {
            await model.updateRunning(id: id, tags: wire, note: noteDraft)
            if model.errorMessage == nil { editingTimerID = nil }
        }
    }
}
