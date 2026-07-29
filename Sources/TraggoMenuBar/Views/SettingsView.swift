import SwiftUI

// The settings window itself (a toolbar-style NSTabViewController) is built in
// SettingsWindowManager. These are the individual section panes it hosts.

// MARK: - Settings (connection + behaviour)

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Storage") {
                // In demo mode the picker disappears entirely: the session is
                // pinned to the demo store, and this note is the mode's one
                // visible indicator (kept out of the popover so screenshots
                // include it only deliberately).
                if model.isDemo {
                    Label("Demo mode", systemImage: "sparkles")
                    Text("Seeded sample data, regenerated on every demo launch. Your real database and settings are untouched — quit and relaunch without PRIMETIME_DEMO to get back to them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let path = model.localDatabasePath {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    storagePicker
                }
            }
            if model.backendKind == .traggo {
                serverSections
            }
            menuAndTagSections
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var storagePicker: some View {
        @Bindable var model = model
        Picker("Keep data", selection: $model.backendKind) {
            Text("On this Mac").tag(BackendKind.local)
            Text("On a Traggo server").tag(BackendKind.traggo)
        }
        .pickerStyle(.segmented)
        if model.backendKind == .local {
            Text("Everything lives in a local database — no server, no account. Connect to a Traggo server here if you have one; each choice keeps its own data.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let path = model.localDatabasePath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Text("Timespans and tag colours live on the server; tag sets and value colours stay on this Mac. Switching back to local storage keeps both sets of data intact.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var serverSections: some View {
        @Bindable var model = model
        Section("Server") {
            TextField("Server URL", text: $model.serverURL)
            TextField("Device name", text: $model.deviceName)
                .help("Shows up under Devices in Traggo, so you can revoke this app.")
        }
        Section("Account") {
            if let user = model.user {
                LabeledContent("Status") {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                LabeledContent("Signed in as", value: user.name)
                Button("Log out", role: .destructive) { model.logout() }
            } else {
                // The sign-in form, demoted here from the popover. The
                // password lives only in local @State and is cleared
                // as soon as a login attempt finishes.
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .onSubmit(submit)
                HStack {
                    if model.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Sign in", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(username.isEmpty || password.isEmpty || model.isBusy)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
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
            Text("How many tag sets the popover lists (0 shows all), in the order from the Tag Sets tab — drag to reorder there. The rest stay a click away behind a “more…” row.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Tags") {
            Toggle("Colour tags by value", isOn: $model.colorTagsByValue)
            Text("Pick a colour per key: value pair, so e.g. repo: foo and repo: bar look different. Pairs without an override keep their key colour.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard !username.isEmpty, !password.isEmpty else { return }
        Task {
            await model.login(username: username, password: password)
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
            Section("Tag set") {
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

    /// In traggo mode the key/value colour split doubles as a server/local
    /// split, which is worth calling out; in local mode both live in the same
    /// database and the story is just "per pair" vs "per key".
    private var colorCaption: String {
        switch (model.colorTagsByValue, model.backendKind) {
        case (true, .traggo):
            "Colours are saved per key: value pair on this Mac and override the key’s server colour. Right-click a swatch to go back to the key colour."
        case (true, .local):
            "Colours are saved per key: value pair and override the key’s colour. Right-click a swatch to go back to the key colour."
        case (false, .traggo):
            "Colours are saved per tag key on the server, so recolouring a key here also changes it in every other tag set that uses it."
        case (false, .local):
            "Colours are saved per tag key, so recolouring a key here also changes it in every other tag set that uses it."
        }
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
