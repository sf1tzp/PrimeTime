import SwiftUI

// The settings window itself (a toolbar-style NSTabViewController) is built in
// SettingsWindowManager. These are the individual section panes it hosts.

// MARK: - Connection

struct ConnectionSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
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
                    LabeledContent("Status") {
                        Label("Not signed in", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    Text("Open the menu-bar popover to log in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tag Sets

struct TagSetsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: TagSet.ID?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            splitView
            Divider()
            VStack(alignment: .leading, spacing: 3) {
                Toggle("Colour tags by value", isOn: $model.colorTagsByValue)
                Text("Pick a colour per key: value pair (stored on this Mac), so e.g. repo: foo and repo: bar look different. Pairs without an override keep their key colour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        // Pre-select the first set so the editor is populated on open.
        .onAppear {
            if selection == nil { selection = model.tagSets.first?.id }
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
            Section("Tags") {
                ForEach($tagSet.tags) { $tag in
                    HStack {
                        colorPicker(for: tag)
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
                Text(model.colorTagsByValue
                     ? "Colours are saved per key: value pair on this Mac and override the key’s server colour. Right-click a swatch to go back to the key colour."
                     : "Colours are saved per tag key on the server, so recolouring a key here also changes it in every other tag set that uses it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// With "colour by value" off (or the value empty) this edits the tag key's
    /// server-side colour, as before. With it on, it edits the local override
    /// for this exact key: value pair instead.
    @ViewBuilder
    private func colorPicker(for tag: TagRow) -> some View {
        let keyEmpty = tag.key.trimmingCharacters(in: .whitespaces).isEmpty
        if model.colorTagsByValue && !tag.value.isEmpty {
            ColorPicker("", selection: Binding(
                get: { model.tagColor(for: tag.key, value: tag.value) },
                set: { model.setValueColor(key: tag.key, value: tag.value, color: $0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(keyEmpty)
            .contextMenu {
                Button("Use key colour") {
                    model.clearValueColor(key: tag.key, value: tag.value)
                }
                .disabled(model.valueColor(key: tag.key, value: tag.value) == nil)
            }
        } else {
            ColorPicker("", selection: Binding(
                get: { model.tagColor(for: tag.key) },
                set: { model.scheduleTagColor(for: tag.key, color: $0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(keyEmpty)
        }
    }
}
