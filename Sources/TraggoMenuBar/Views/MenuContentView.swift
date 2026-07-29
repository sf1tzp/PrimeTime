import SwiftUI
import AppKit

/// The contents of the menu-bar popover.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model

    /// Local draft of the running timer's note, synced from the server when the
    /// active timer changes (not on every poll, so it won't clobber typing).
    @State private var noteDraft = ""

    /// Whether the running timer's tags are being edited in place, and a local
    /// draft of them. Seeded on entering edit mode so a background poll can't
    /// clobber edits; discarded when the active timer changes.
    @State private var editingTags = false
    @State private var tagDrafts: [TagRow] = []

    /// Set when starting a blank timer so that, once the new timer lands, we
    /// open the tag editor instead of resetting it — "start → describe" as one
    /// gesture. Consumed by the `activeTimer` change handler.
    @State private var editTagsOnNextTimer = false

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
            noteDraft = model.activeTimer?.note ?? ""
        }
        .onChange(of: model.activeTimer?.id) {
            noteDraft = model.activeTimer?.note ?? ""
            if editTagsOnNextTimer, model.activeTimer != nil {
                editTagsOnNextTimer = false
                tagDrafts = [TagRow()]   // one empty row, ready to type into
                editingTags = true
            } else {
                editingTags = false
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
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.tagSets) { set in
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
                    // Enforce one active timer at a time: must stop before starting.
                    .disabled(model.activeTimer != nil || model.isBusy)
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

        // Full-width rows, like Rectangle's menu: quick access to the history
        // tabs of the settings window, then Settings and Quit.
        VStack(spacing: 2) {
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
                openSettings(tab: .connection)
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

    @ViewBuilder
    private var activeTimerSection: some View {
        if let active = model.activeTimer {
            VStack(alignment: .leading, spacing: 6) {
                Text("Running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.elapsedString(since: active.start.date))
                    .font(.system(.title2, design: .monospaced))
                    .monospacedDigit()
                if editingTags {
                    tagEditor
                } else {
                    activeTagsDisplay(active.tags ?? [])
                }
                HStack {
                    TextField("Add a note…", text: $noteDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveNote() }
                    if noteDraft != active.note {
                        Button("Save") { saveNote() }
                            .disabled(model.isBusy)
                    }
                }
                Button("Stop", role: .destructive) {
                    Task { await model.stop() }
                }
                .disabled(model.isBusy)
            }
        } else {
            // In place of a "no active timer" placeholder: an ad-hoc start with
            // no tags — capture time first, classify it in the tag editor while
            // the clock runs.
            Button {
                editTagsOnNextTimer = true
                Task {
                    await model.start(tags: [])
                    if model.errorMessage != nil { editTagsOnNextTimer = false }
                }
            } label: {
                Label("Start blank timer", systemImage: "circle.dashed")
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(model.isBusy)
        }
    }

    /// Read-only tag pills for the running timer, with a pencil to edit them.
    /// The pencil shows even with no tags so the user can add the first one.
    @ViewBuilder
    private func activeTagsDisplay(_ tags: [TimeSpanTag]) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if tags.isEmpty {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(tags.indices, id: \.self) { i in
                        TagPill(key: tags[i].key, value: tags[i].value,
                                color: model.tagColor(for: tags[i].key, value: tags[i].value))
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                beginEditingTags()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit tags")
        }
    }

    /// Inline row editor for the running timer's tags — one row per tag (colour
    /// swatch, key, value, remove), plus Add / Cancel / Save. Save commits the
    /// draft to the server via `updateActiveTags`.
    private var tagEditor: some View {
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
            HStack {
                Button {
                    tagDrafts.append(TagRow())
                } label: {
                    Label("Add tag", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Cancel") { editingTags = false }
                    .buttonStyle(.borderless)
                Button("Save") { saveTags() }
                    .disabled(model.isBusy)
            }
        }
    }

    private func beginEditingTags() {
        tagDrafts = (model.activeTimer?.tags ?? [])
            .map { TagRow(key: $0.key, value: $0.value) }
        editingTags = true
    }

    private func saveTags() {
        let wire = tagDrafts.wireTags
        Task {
            await model.updateActiveTags(wire)
            if model.errorMessage == nil { editingTags = false }
        }
    }

    private func saveNote() {
        Task { await model.updateNote(noteDraft) }
    }
}
