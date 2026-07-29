import SwiftUI

/// A menu row that highlights (accent-filled, white text) on mouse-over, like
/// Rectangle's status-menu rows. Disabled rows dim and don't highlight.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var highlighted: Bool { hovering && isEnabled }

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(highlighted ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
                .onHover { hovering = $0 }
        }
    }
}

/// A tag shown as a coloured capsule ("key: value"), coloured by the tag's
/// server-side colour.
struct TagPill: View {
    let key: String
    let value: String
    let color: Color

    var body: some View {
        Text(value.isEmpty ? key : "\(key): \(value)")
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
            .foregroundStyle(color.contrastingTextColor)
    }
}

/// A colour swatch for a tag. With "colour by value" on (and a non-empty
/// value) it edits the local per-`key: value` override; otherwise it edits the
/// tag key's server-side colour. Disabled when the key is blank. Shared by the
/// Tag Sets settings pane and the running-timer tag editor.
struct TagColorPicker: View {
    @Environment(AppModel.self) private var model
    let key: String
    let value: String

    private var keyEmpty: Bool { key.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        if model.colorTagsByValue && !value.isEmpty {
            ColorPicker("", selection: Binding(
                get: { model.tagColor(for: key, value: value) },
                set: { model.setValueColor(key: key, value: value, color: $0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(keyEmpty)
            .contextMenu {
                Button("Use key colour") {
                    model.clearValueColor(key: key, value: value)
                }
                .disabled(model.valueColor(key: key, value: value) == nil)
            }
        } else {
            ColorPicker("", selection: Binding(
                get: { model.tagColor(for: key) },
                set: { model.scheduleTagColor(for: key, color: $0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(keyEmpty)
        }
    }
}

/// A simple left-to-right flow layout that wraps to the next line when it runs
/// out of width — used for rows of `TagPill`s.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0
        var rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                widest = max(widest, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
