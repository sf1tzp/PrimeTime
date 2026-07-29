import SwiftUI

/// The "see everything" surface complementing the popover's capped Quick start
/// list (#7): every tag set as a clickable card in a grid. Clicking a card
/// starts the set, same as a Quick start row.
struct LauncherView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            // The trailing ＋ card doubles as the empty state: with no sets
            // saved, the grid is just the invitation to create one.
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.tagSets) { set in
                    TagSetCard(set: set)
                }
                NewTagSetCard()
            }
            .padding(16)
        }
    }
}

/// The trailing "create" tile: dashed outline, no fill, so it reads as an
/// action rather than a set. Opens the Tag Sets pane on a fresh set.
private struct NewTagSetCard: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.newTagSet()
            SettingsWindowManager.shared.show(model: model, tab: .tagSets)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 28))
                Text("New Label Set")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.secondary.opacity(hovering ? 0.7 : 0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Create a tag set")
    }
}

/// One launcher card: the set's icon and name on a tile tinted with the first
/// tag's colour (accent when the set has no tags). Clicking starts the set —
/// alongside any running timers (overlapping timespans are supported); only a
/// set that is itself running deactivates, matching how the Quick start list
/// hides running sets.
private struct TagSetCard: View {
    @Environment(AppModel.self) private var model
    let set: TagSet
    @State private var hovering = false

    private var tint: Color {
        if let first = set.labels.first {
            return model.tagColor(for: first.key, value: first.value)
        }
        return .accentColor
    }

    private var isRunning: Bool { model.isRunning(set) }
    private var startable: Bool { !isRunning && !model.isBusy }

    var body: some View {
        Button {
            Task { await model.start(tagSet: set) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: set.symbol)
                    .font(.system(size: 28))
                Text(set.name.isEmpty ? "Untitled" : set.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .foregroundStyle(tint.contrastingTextColor)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(hovering && startable ? 0.6 : 0),
                                  lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!startable)
        .opacity(startable ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(isRunning
              ? "Already running — stop it from the menu bar"
              : set.labels.isEmpty
              ? "Start with no tags"
              : "Start " + set.labels.map {
                    $0.value.isEmpty ? $0.key : "\($0.key): \($0.value)"
                }.joined(separator: ", "))
    }
}
