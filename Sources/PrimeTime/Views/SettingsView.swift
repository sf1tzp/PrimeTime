import SwiftUI

// The settings window itself (a toolbar-style NSTabViewController) is built in
// SettingsWindowManager. These are the individual section panes it hosts.

// MARK: - Settings (connection + behaviour)

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""
    @State private var syncURL = ""
    @State private var syncUsername = ""
    @State private var syncPassword = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Storage") {
                // In demo mode the section is pinned to the demo store, and
                // this note is the mode's one visible indicator (kept out of
                // the popover so screenshots include it only deliberately).
                if model.isDemo {
                    Label("Demo mode", systemImage: "sparkles")
                    Text("Seeded sample data, regenerated on every demo launch. Your real database and settings are untouched — quit and relaunch without PRIMETIME_DEMO to get back to them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Everything lives in a local database — no server, no account needed. Connect a sync server below to share your data across Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let path = model.localDatabasePath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            // A demo must never reach a real server: no sync, no import.
            if !model.isDemo {
                syncSection
                importSection
            }
            menuAndTagSections
        }
        .formStyle(.grouped)
    }

    // MARK: Sync server (#33)

    /// Connect-to-sync-server flow, and the connection's status once made.
    /// Wording stays product-neutral ("sync server") — the app's own rename
    /// is #34.
    @ViewBuilder
    private var syncSection: some View {
        @Bindable var model = model
        Section("Sync") {
            if let engine = model.syncEngine, let server = model.syncServer {
                LabeledContent("Server", value: server.url)
                LabeledContent("Account", value: server.userName)
                LabeledContent("Status") {
                    switch engine.status {
                    case .syncing:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Syncing…")
                        }
                    case .idle:
                        Label(lastSyncedText(engine.lastSyncedAt),
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .error:
                        Label("Offline — changes will sync when the server is reachable",
                              systemImage: "exclamationmark.arrow.circlepath")
                            .foregroundStyle(.orange)
                    }
                }
                if case .error(let message) = engine.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack {
                    Button("Sync now") { Task { await engine.syncNow() } }
                        .disabled(engine.status == .syncing)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        model.disconnectSyncServer()
                    }
                }
                Text("Everything syncs: timespans, tag keys and colours, tag sets, and the settings below. Edits made offline catch up on the next sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Optional: connect a sync server to share timespans, tag sets, and colours across your Macs. Everything keeps working offline; changes sync in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Server URL", text: $syncURL)
                    .autocorrectionDisabled()
                TextField("Username", text: $syncUsername)
                    .autocorrectionDisabled()
                SecureField("Password", text: $syncPassword)
                    .onSubmit(connect)
                TextField("Device name", text: $model.deviceName)
                    .help("How this Mac appears in the server's device list, so you can revoke it later.")
                HStack {
                    if model.isConnectingSync {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Connect", action: connect)
                        .disabled(syncURL.isEmpty || syncUsername.isEmpty
                            || syncPassword.isEmpty || model.isConnectingSync)
                }
                if let error = model.syncConnectError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
    }

    private func lastSyncedText(_ date: Date?) -> String {
        guard let date else { return "Connected" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func connect() {
        guard !syncURL.isEmpty, !syncUsername.isEmpty, !syncPassword.isEmpty else { return }
        Task {
            await model.connectSyncServer(url: syncURL, username: syncUsername,
                                          password: syncPassword)
            syncPassword = ""   // never keep the password around
        }
    }

    @ViewBuilder
    private var menuAndTagSections: some View {
        @Bindable var model = model
        Section("Menu") {
            // A plain numeric field with its own stepper, like the log
            // editor's time fields. Typed values are clamped on commit.
            let limit = Binding(
                get: { model.menuTagSetLimit },
                set: { model.menuTagSetLimit = max(0, min(99, $0)) })
            LabeledContent("Quick-start tag sets") {
                HStack(spacing: 2) {
                    TextField("", value: limit, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 40)
                    Stepper("", value: limit, in: 0...99)
                        .labelsHidden()
                }
            }
            Text("How many label sets the popover lists (0 shows all), in the order from the Label Sets tab — drag to reorder there. The rest stay a click away behind a “more…” row.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Tags") {
            Toggle("Colour tags by value", isOn: $model.colorTagsByValue)
            Text("Pick a colour per key: value pair, so e.g. repo: foo and repo: bar look different. Pairs without an override keep their key colour.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // Sparkle (#46). Absent from dev builds and demos, where there is no
        // updater to configure.
        if model.updater.isAvailable {
            @Bindable var updater = model.updater
            Section("Updates") {
                Toggle("Check for updates in the background",
                       isOn: $updater.automaticallyChecksForUpdates)
                Text("Checks about once a day and offers new versions when they appear. Off means updates only come from “Check for Updates…” in the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Import from traggo (#30)

    /// The one-shot importer's surface. Reuses the saved traggo session when
    /// one exists; otherwise asks for a one-off sign-in whose token is kept,
    /// so re-runs are already signed in.
    private var importSection: some View {
        @Bindable var model = model
        return Section("Import from Traggo") {
            Text("Copy a Traggo server’s full history — finished and running timespans, plus tag keys and their colours — into the local database. Safe to run again: timespans already imported are updated, not duplicated.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Server URL", text: $model.serverURL)
            if model.hasTraggoSession {
                Text("Using the saved Traggo sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            HStack {
                if model.isImporting {
                    ProgressView().controlSize(.small)
                    Text("Imported \(model.importedSpanCount) timespans…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import from Traggo…", action: runImport)
                    .disabled(model.isImporting
                        || (!model.hasTraggoSession && (username.isEmpty || password.isEmpty)))
            }
            if let summary = model.importSummary {
                Label(summaryText(summary), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = model.importError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private func summaryText(_ summary: ImportSummary) -> String {
        var parts = ["Imported \(summary.spansImported) timespans"]
        if summary.spansUpdated > 0 {
            parts.append("(\(summary.spansInserted) new, \(summary.spansUpdated) updated)")
        }
        if summary.runningSpans > 0 {
            parts.append("— \(summary.runningSpans) still running —")
        }
        parts.append("and \(summary.definitionsCreated + summary.definitionsRecolored) tag keys.")
        return parts.joined(separator: " ")
    }

    private func runImport() {
        Task {
            await model.importFromTraggo(username: username, password: password)
            password = ""   // never keep the password around
        }
    }
}

// MARK: - Tag Sets

struct TagSetsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: TagSet.ID?

    var body: some View {
        splitView
            // Pre-select a set so the editor is populated on open: one handed
            // over from another surface (Log ＋ / Launcher ＋ card) wins,
            // otherwise the first set.
            .onAppear { consumePendingSelection() }
            .onChange(of: model.pendingTagSetSelection) { consumePendingSelection() }
    }

    private func consumePendingSelection() {
        if let pending = model.pendingTagSetSelection {
            selection = pending
            model.pendingTagSetSelection = nil
        } else if selection == nil {
            selection = model.tagSets.first?.id
        }
    }

    private var splitView: some View {
        @Bindable var model = model
        return HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.tagSets) { set in
                        Text(set.name.isEmpty ? "Untitled" : set.name)
                            .tag(set.id)
                    }
                    .onDelete { model.tagSets.remove(atOffsets: $0) }
                    // Order matters: the popover shows the first N sets.
                    .onMove { model.tagSets.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack {
                    Button {
                        let set = TagSet(name: "New tag set")
                        model.tagSets.append(set)
                        selection = set.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let selection,
                           let index = model.tagSets.firstIndex(where: { $0.id == selection }) {
                            model.tagSets.remove(at: index)
                        }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 160)

            if let index = model.tagSets.firstIndex(where: { $0.id == selection }) {
                TagSetDetailView(tagSet: $model.tagSets[index])
            } else {
                VStack {
                    Spacer()
                    Text("Select or add a tag set")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct TagSetDetailView: View {
    @Environment(AppModel.self) private var model
    @Binding var tagSet: TagSet

    var body: some View {
        Form {
            Section("Label set") {
                TextField("Name", text: $tagSet.name)
            }
            Section("Launcher icon") {
                SymbolPicker(selection: $tagSet.symbolName)
            }
            Section("Tags") {
                ForEach($tagSet.tags) { $tag in
                    HStack {
                        TagColorPicker(key: tag.key, value: tag.value)
                        TextField("key", text: $tag.key)
                            .autocorrectionDisabled()
                        Text(":").foregroundStyle(.secondary)
                        TextField("value", text: $tag.value)
                        Button(role: .destructive) {
                            tagSet.tags.removeAll { $0.id == tag.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    tagSet.tags.append(TagRow())
                } label: {
                    Label("Add tag", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Text("Keys are lower-cased with spaces turned into “-”. Missing keys are created automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(colorCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Key and value colours both live in the local database (and follow the
    /// user across Macs once a sync server is connected), so the story is
    /// just "per pair" vs "per key".
    private var colorCaption: String {
        model.colorTagsByValue
            ? "Colours are saved per key: value pair and override the key’s colour. Right-click a swatch to go back to the key colour."
            : "Colours are saved per tag key, so recolouring a key here also changes it in every other tag set that uses it."
    }
}

/// A curated SF Symbols grid for the launcher-card icon — deliberately not a
/// full symbol browser. `nil` selection renders (and highlights) the default
/// "tag" symbol.
private struct SymbolPicker: View {
    @Binding var selection: String?

    private static let choices = [
        "tag", "laptopcomputer", "terminal", "hammer", "wrench.and.screwdriver",
        "doc.text", "book", "graduationcap", "brain", "lightbulb",
        "person.2", "phone", "envelope", "bubble.left.and.bubble.right", "calendar",
        "cup.and.saucer", "fork.knife", "figure.walk", "figure.run", "bed.double",
        "house", "car", "cart", "globe", "leaf",
        "gamecontroller", "music.note", "paintbrush", "camera", "shippingbox",
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 4)],
                  spacing: 4) {
            ForEach(Self.choices, id: \.self) { symbol in
                let selected = symbol == (selection ?? "tag")
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Color.accentColor.opacity(0.25) : .clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selected ? Color.accentColor : .clear))
                }
                .buttonStyle(.borderless)
                .help(symbol)
            }
        }
        .padding(.vertical, 2)
    }
}
