import SwiftUI
import AppKit

/// The contents of the menu-bar popover.
struct MenuContentView: View {
    @Environment(AppModel.self) private var model

    /// Local draft of the running timer's note, synced from the server when the
    /// active timer changes (not on every poll, so it won't clobber typing).
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
            noteDraft = model.activeTimer?.note ?? ""
        }
        .onChange(of: model.activeTimer?.id) {
            noteDraft = model.activeTimer?.note ?? ""
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
                                                color: model.tagColor(for: tag.key))
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

        // Settings and Quit as separate full-width rows, like Rectangle's menu.
        VStack(spacing: 2) {
            Button {
                openSettings()
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

    private func openSettings() {
        SettingsWindowManager.shared.show(model: model)
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
                if let tags = active.tags, !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags.indices, id: \.self) { i in
                            TagPill(key: tags[i].key, value: tags[i].value,
                                    color: model.tagColor(for: tags[i].key))
                        }
                    }
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
            HStack {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                Text("No active timer")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveNote() {
        Task { await model.updateNote(noteDraft) }
    }
}
