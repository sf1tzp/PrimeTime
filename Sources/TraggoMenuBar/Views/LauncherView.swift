import SwiftUI

/// The "see everything" surface complementing the popover's capped Quick start
/// list (#7): every tag set as a clickable card in a grid. Clicking a card
/// starts the set, same as a Quick start row.
struct LauncherView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            if model.tagSets.isEmpty {
                Text("No tag sets yet — add some in the Tag Sets tab.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.tagSets) { set in
                        TagSetCard(set: set)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// One launcher card: the set's icon and name on a tile tinted with the first
/// tag's colour (accent when the set has no tags). Follows the Quick start
/// rows' rule: plain click starts the set, disabled while a timer runs.
private struct TagSetCard: View {
    @Environment(AppModel.self) private var model
    let set: TagSet
    @State private var hovering = false

    private var tint: Color {
        if let first = set.wireTags.first {
            return model.tagColor(for: first.key, value: first.value)
        }
        return .accentColor
    }

    private var startable: Bool { model.activeTimer == nil && !model.isBusy }

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
        .help(set.wireTags.isEmpty
              ? "Start with no tags"
              : "Start " + set.wireTags.map {
                    $0.value.isEmpty ? $0.key : "\($0.key): \($0.value)"
                }.joined(separator: ", "))
    }
}
