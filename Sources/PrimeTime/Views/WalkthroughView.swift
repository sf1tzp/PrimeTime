import SwiftUI
import AppKit
import Charts
import PrimeTimeCore

/// The interactive walkthrough of the label model (issue #93), presented as
/// seven Next/Back pages. Every page reads and mutates the one shared
/// `WalkthroughModel`, so state carries across pages deliberately: a smell
/// activated on page 4 keeps corrupting the charts until it is healed.
///
/// - `walkthrough` — the shared dataset: the demo week, the group-by key, the
///   schema-smell selection, aggregation, and colours.
/// - `onBack` — return to the Welcome step.
/// - `onContinue` — end onboarding (finished *or* skipped); the caller closes
///   the window and opens the Label Sets tab.
struct WalkthroughView: View {
    @Bindable var walkthrough: WalkthroughModel
    var onBack: () -> Void
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    /// Whether the last navigation went forward — decides the slide direction.
    @State private var forward = true

    private static let pageCount = 7

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Group {
                    switch page {
                    case 0: SpanIsLabelsPage(walkthrough: walkthrough)
                    case 1: AggregatePage(walkthrough: walkthrough)
                    case 2: LabelingSchemesPage()
                    case 3: SmellsPage(walkthrough: walkthrough)
                    case 4: LabelSetsPage(walkthrough: walkthrough)
                    case 5: QuickLabelsPage(walkthrough: walkthrough)
                    default: SurfacesPage()
                    }
                }
                .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()   // sliding pages must not escape the fixed window

            progressDots
            Divider()
            OnboardingFooter(back: goBack,
                             primaryTitle: page == Self.pageCount - 1 ? "Continue" : "Next",
                             primaryAction: goNext) {
                Button("Skip Tour", action: onContinue)
            }
        }
        // Healing a smell can strand the page-2 picker on a key the dataset no
        // longer has (e.g. `proj` after healing drifting keys) — fall back.
        .onChange(of: walkthrough.groupableKeys) { _, keys in
            if !keys.contains(walkthrough.groupKey) { walkthrough.groupKey = "repo" }
        }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return forward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    private func go(to target: Int) {
        forward = target > page
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { page = target }
    }

    private func goBack() {
        if page == 0 { onBack() } else { go(to: page - 1) }
    }

    private func goNext() {
        if page == Self.pageCount - 1 { onContinue() } else { go(to: page + 1) }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.bottom, 10)
        .accessibilityLabel("Page \(page + 1) of \(Self.pageCount)")
    }
}

// MARK: - Shared page chrome

/// Common scaffold: mono step numeral (HelpView's rule style) + heading +
/// one-line subtitle, then the page's interactive hero filling the rest.
/// Top padding keeps the heading clear of the floating traffic lights.
private struct WalkthroughPage<Content: View>: View {
    let index: Int
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", index + 1))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.title2.weight(.semibold))
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    /// Clickable-thing affordance for mock UI that lacks the system button
    /// look.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    /// One-time discoverability glow (driven by the caller's state; callers
    /// never turn it on under Reduce Motion).
    func discoveryGlow(_ on: Bool) -> some View {
        shadow(color: Color.accentColor.opacity(on ? 0.9 : 0), radius: on ? 5 : 0)
    }
}

// MARK: - Page 1: a span is its labels

private struct SpanIsLabelsPage: View {
    @Bindable var walkthrough: WalkthroughModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The mock timer: a fake base offset that keeps ticking while "running".
    @State private var baseElapsed: TimeInterval = 42 * 60 + 17
    @State private var runningSince: Date? = Date()

    // The inline editor, mirroring the popover's `timerEditor`.
    @State private var editing = false
    @State private var tagDrafts: [TagRow] = []
    @State private var noteDraft = ""

    /// Which editor field holds focus — commits ride on its changes, so
    /// Return *or* clicking away updates the pills reactively.
    private enum EditorField: Hashable {
        case key(UUID), value(UUID), note
    }
    @FocusState private var focusedField: EditorField?

    /// One-time pulse pointing at the interactive bits; never under Reduce
    /// Motion.
    @State private var pulsing = false

    private var anim: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    var body: some View {
        WalkthroughPage(index: 0, title: "A timer is nothing without its labels",
                        subtitle: "No folders, no project tree — a timer records a stretch of time plus key: value labels and notes. This one is live: try it.") {
            VStack(alignment: .leading, spacing: 14) {
                mockPopoverCard
                Text(walkthrough.mockupSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("You can always start a blank timer and label it later, if you want.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear(perform: startPulse)
    }

    private func startPulse() {
        guard !reduceMotion, !pulsing else { return }
        withAnimation(.easeInOut(duration: 0.6).delay(0.6).repeatCount(5, autoreverses: true)) {
            pulsing = true
        }
        Task {
            try? await Task.sleep(for: .seconds(4.2))
            withAnimation(.easeOut(duration: 0.6)) { pulsing = false }
        }
    }

    /// A compact working rendition of the real popover's running row.
    private var mockPopoverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(runningSince == nil ? "Stopped" : "Running")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                elapsedText
                if walkthrough.mockupLabels.isEmpty {
                    Text("No labels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(walkthrough.mockupLabels, id: \.self) { label in
                            removablePill(label)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    editing ? cancelEditing() : beginEditing()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(HoverIconButtonStyle())
                .pointingHandCursor()
                .discoveryGlow(pulsing)
                .help("Edit labels and note")
                Button(action: toggleTimer) {
                    Image(systemName: runningSince == nil ? "play.fill" : "stop.fill")
                }
                .buttonStyle(HoverIconButtonStyle())
                .pointingHandCursor()
                .discoveryGlow(pulsing)
                .help(runningSince == nil ? "Start again" : "Stop")
            }
            if !editing, !walkthrough.mockupNote.isEmpty {
                Text(walkthrough.mockupNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            if editing {
                mockEditor
            }
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var elapsedText: some View {
        // Ticks while running; a plain frozen Text while stopped (no need to
        // keep a timeline alive for a static value).
        if let since = runningSince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.clock(baseElapsed + max(0, context.date.timeIntervalSince(since))))
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        } else {
            Text(Self.clock(baseElapsed))
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private static func clock(_ elapsed: TimeInterval) -> String {
        let seconds = Int(elapsed)
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func toggleTimer() {
        if let since = runningSince {
            baseElapsed += max(0, Date().timeIntervalSince(since))
            runningSince = nil
        } else {
            runningSince = Date()
        }
    }

    /// Only the ⨯ removes — the pill body is a fact, not a button.
    private func removablePill(_ label: SpanLabel) -> some View {
        let color = WalkthroughModel.color(key: label.key, value: label.value)
        return HStack(spacing: 4) {
            Text("\(label.key): \(label.value)")
            Button {
                withAnimation(anim) { walkthrough.removeMockup(label) }
                // Keep an open editor in step, or its next commit would
                // resurrect the pill.
                tagDrafts.removeAll { $0.key == label.key && $0.value == label.value }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Remove \(label.key): \(label.value)")
        }
        .font(.caption2)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(color))
        .foregroundStyle(color.contrastingTextColor)
    }

    // MARK: The inline editor (mirrors MenuContentView.timerEditor)

    /// Same rows as the real editor, minus `TagColorPicker` — that writes the
    /// user's colour store, which the walkthrough's demo data must not touch —
    /// so a static swatch stands in. Return in a label field, or focus moving
    /// anywhere, commits the drafts to the pills; Done just closes.
    private var mockEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($tagDrafts) { $tag in
                HStack(spacing: 6) {
                    TagColorChip(color: WalkthroughModel.color(key: tag.key,
                                                               value: tag.value))
                    TextField("key", text: $tag.key)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .frame(width: LabelEditorStyle.keyFieldWidth)
                        .focused($focusedField, equals: .key(tag.id))
                        .onSubmit(commitEdits)
                    Text(":").foregroundStyle(.secondary)
                    TextField("value", text: $tag.value)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .value(tag.id))
                        .onSubmit(commitEdits)
                    Button(role: .destructive) {
                        // Read the id before removeAll — reading the `tag`
                        // binding inside the predicate re-enters the array's
                        // exclusive access and traps.
                        let id = tag.id
                        tagDrafts.removeAll { $0.id == id }
                        commitEdits()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                tagDrafts.append(TagRow())
            } label: {
                Label("Add Label", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            TextField("Add a note…", text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .note)
                .onSubmit(saveEdits)
            HStack {
                Spacer()
                Button("Cancel", action: cancelEditing)
                    .buttonStyle(.borderless)
                Button("Done", action: saveEdits)
            }
        }
        // "Clicking off" a field is a focus change — commit on every move,
        // so the pills above always mirror the fields.
        .onChange(of: focusedField) { _, _ in commitEdits() }
    }

    private func beginEditing() {
        let rows = walkthrough.mockupLabels.map { TagRow(key: $0.key, value: $0.value) }
        tagDrafts = rows.isEmpty ? [TagRow()] : rows
        noteDraft = walkthrough.mockupNote
        withAnimation(anim) { editing = true }
    }

    private func cancelEditing() {
        withAnimation(anim) { editing = false }
    }

    /// Push the drafts into the pills without closing the editor.
    private func commitEdits() {
        withAnimation(anim) {
            walkthrough.commitMockup(labels: tagDrafts.labels, note: noteDraft)
        }
    }

    private func saveEdits() {
        commitEdits()
        withAnimation(anim) { editing = false }
    }
}

// MARK: - Page 2: labels aggregate

private struct AggregatePage: View {
    @Bindable var walkthrough: WalkthroughModel

    var body: some View {
        WalkthroughPage(index: 1, title: "Labels group up",
                        subtitle: "This is what a typical week of labelled time spans looks like. See where time was spent simply by grouping these labels together.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 20) {
                    weekList
                    MiniChartsPane(walkthrough: walkthrough)
                        .frame(width: 270)
                }
                Text("Colours follow labels around: the same color on the labels and in the charts. Customize colors to your liking in Settings!")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var weekList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let byDay = Dictionary(grouping: walkthrough.spans, by: \.day)
                ForEach(byDay.keys.sorted(), id: \.self) { day in
                    HStack(alignment: .top, spacing: 8) {
                        Text(walkthrough.date(day: day), format: .dateTime.weekday(.abbreviated))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(byDay[day] ?? []) { span in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(formatDuration(span.seconds))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 42, alignment: .trailing)
                                    FlowLayout(spacing: 4) {
                                        ForEach(span.labels, id: \.self) { label in
                                            TagPill(key: label.key, value: label.value,
                                                    color: WalkthroughModel.color(key: label.key,
                                                                                  value: label.value))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 6)
        }
    }
}

/// Mini donut + stacked daily bar fed by the shared model — the same pane
/// sits on pages 2 and 4 so corruptions carry over visibly. Page 2 exposes
/// the group-by picker; page 4 passes `fixedKey` to pin the grouping to the
/// key each smell damages best. Chart mutations animate because every write
/// (picker, smell selection) happens inside `withAnimation`.
private struct MiniChartsPane: View {
    @Bindable var walkthrough: WalkthroughModel
    /// When set, charts pin to this key and the picker is replaced by a
    /// caption.
    var fixedKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var key: String { fixedKey ?? walkthrough.groupKey }

    var body: some View {
        let totals = walkthrough.totals(by: key)
        let colors = walkthrough.colorMap(for: totals, key: key)
        VStack(alignment: .leading, spacing: 10) {
            if fixedKey == nil {
                Picker("Group by", selection: animatedGroupKey) {
                    ForEach(walkthrough.groupableKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .fixedSize()
            } else {
                (Text("Grouped by ").foregroundStyle(.secondary)
                    + Text(key).fontWeight(.semibold))
                    .font(.caption)
            }
            HStack {
                Spacer(minLength: 0)
                donut(totals, colors: colors)
                Spacer(minLength: 0)
            }
            legend(totals, colors: colors)
            dailyBar(colors: colors)
        }
    }

    /// Routes picker writes through `withAnimation` so both charts re-slice
    /// rather than jump.
    private var animatedGroupKey: Binding<String> {
        Binding(get: { walkthrough.groupKey },
                set: { key in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                        walkthrough.groupKey = key
                    }
                })
    }

    private func donut(_ totals: [SeriesTotal], colors: [String: Color]) -> some View {
        let missing = walkthrough.missingSeconds(for: key)
        return Chart(totals) { item in
            SectorMark(angle: .value("Time", item.seconds),
                       innerRadius: .ratio(0.62),
                       angularInset: 1.5)
                .foregroundStyle(colors[item.label] ?? .gray)
                .cornerRadius(2)
        }
        .chartLegend(.hidden)   // the compact legend below is the legend
        .frame(width: 140, height: 140)
        .overlay {
            // The centre stays empty — the slices are the story — except
            // when a smell is hiding hours: then it names the loss.
            if missing > 0 {
                VStack(spacing: 0) {
                    Text("time missing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("~\(Int((missing / 3600).rounded()))h")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }
        }
    }

    private func legend(_ totals: [SeriesTotal], colors: [String: Color]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(totals) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(colors[item.label] ?? .gray)
                        .frame(width: 6, height: 6)
                    Text(item.label)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
    }

    private func dailyBar(colors: [String: Color]) -> some View {
        Chart(walkthrough.dailyTotals(by: key)) { item in
            BarMark(x: .value("Day", item.day, unit: .day),
                    y: .value("Hours", item.seconds / 3600))
                .foregroundStyle(colors[item.label] ?? .gray)
                .cornerRadius(2)
        }
        .chartLegend(.hidden)
        // Pin to the whole demo week or sparse data would stretch its bars.
        .chartXScale(domain: walkthrough.weekInterval.start...walkthrough.weekInterval.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 96)
    }
}

// MARK: - Page 3: labeling schemes

/// Static copy page between the aggregation demo and the smells: keep the
/// scheme small, put the overflow in notes — so "don't grow the scheme"
/// lands before the ways a grown scheme goes wrong.
private struct LabelingSchemesPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One entry in the rotating hero: a scheme's keys, and the caption
    /// tying its dimension count to the work it runs.
    private struct Scheme {
        let keys: [String]
        let caption: String
    }

    /// Good schemes at every dimensionality, building up — one key is
    /// enough for a bookshelf, four run a software shop.
    private static let schemes: [Scheme] = [
        Scheme(keys: ["book"],
               caption: "A simple 'book' label can track any number of books."),
        Scheme(keys: ["project", "type"],
               caption: "Two labels can cover most general types of work."),
        Scheme(keys: ["repo", "feat", "client", "type"],
               caption: "Four labels can cover complex workflows."),
    ]

    @State private var schemeIndex = 0

    var body: some View {
        WalkthroughPage(index: 2, title: "Labeling schemes",
                        subtitle: "Don't overcomplicate it — a timer that accumulates half a dozen or more labels gets complicated fast.") {
            VStack(alignment: .leading, spacing: 14) {
                rotatingSchemes

                Text("Things will pop up that feel like they should be a label but don't fit your scheme — write those as notes instead:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                dilemmaCard

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(.tint)
                    Text("Label Review shows when notes develop a trend — problem: this, problem: that. If you notice that happening, it's okay to add to your scheme. Decide what works best in your workflow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("PrimeTime lets you save custom labeling schemes as Label Sets — even a label whose value you leave blank and fill in as the timer starts. More on this later.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// The rotating hero: one scheme's key pills over its caption, fading
    /// to the next every few seconds. The cycle still runs under Reduce
    /// Motion (it is content, not decoration) — only the cross-fade goes.
    private var rotatingSchemes: some View {
        ZStack {
            let scheme = Self.schemes[schemeIndex]
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    ForEach(scheme.keys, id: \.self) { key in
                        keyPill(key)
                    }
                }
                Text(scheme.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id(schemeIndex)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                    schemeIndex = (schemeIndex + 1) % Self.schemes.count
                }
            }
        }
    }

    /// The temptation and its answer: the one-off that "feels" like a label,
    /// kept as a note so the context sticks to the span without a new key.
    private var dilemmaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("“I'm on the backend feature but went down a rabbit hole setting up CA trust — should I label it problem: certificate-trust?”")
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            (Text("No — ").fontWeight(.semibold)
                + Text("this information is better suited for a Note. Notes stick with the time span, so the context is preserved without complicating the scheme."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("1:12:07")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 3) {
                    FlowLayout(spacing: 4) {
                        TagPill(key: "repo", value: "sfi/backend",
                                color: WalkthroughModel.color(key: "repo",
                                                              value: "sfi/backend"))
                        TagPill(key: "feat", value: "registry-auth",
                                color: WalkthroughModel.color(key: "feat",
                                                              value: "registry-auth"))
                    }
                    Text("Rabbit hole: CA trust for the internal registry.")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func keyPill(_ key: String) -> some View {
        let color = WalkthroughModel.keyColor(key)
        return Text("\(key):")
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
            .foregroundStyle(color.contrastingTextColor)
    }
}

// MARK: - Page 4: why schemes fail

private struct SmellsPage: View {
    @Bindable var walkthrough: WalkthroughModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WalkthroughPage(index: 3, title: "Why schemes fail",
                        subtitle: "Four ways a labeling scheme goes wrong — PrimeTime helps you dodge all of these by defining your labels up front. Click a card to corrupt the week; click it again and the charts heal.") {
            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(WalkthroughModel.SchemaSmell.allCases) { smell in
                            smellCard(smell)
                        }
                    }
                    .padding(.trailing, 6)
                }
                VStack(alignment: .leading, spacing: 8) {
                    // Each smell pins the charts to the key that shows its
                    // damage best; healthy weeks default to repo.
                    MiniChartsPane(walkthrough: walkthrough,
                                   fixedKey: walkthrough.activeSmell?.demoKey ?? "repo")
                    if let smell = walkthrough.activeSmell {
                        smellDetail(smell)
                    } else {
                        Label {
                            Text("A healthy scheme: every label lands in a slice, and both charts tell one story.")
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                        }
                        .font(.caption)
                    }
                }
                .frame(width: 260)
            }
        }
    }

    /// The red callout beside the corrupted charts. Fused facts and drifting
    /// keys get bespoke treatments — the one-line `sideEffect` wasn't enough
    /// to make their counter-examples land for a new user.
    /// (fixedSize throughout: the column is height-constrained and a tall
    /// legend would otherwise squeeze the text to one truncated line.)
    @ViewBuilder
    private func smellDetail(_ smell: WalkthroughModel.SchemaSmell) -> some View {
        switch smell {
        case .fusedFacts:
            // Lead with the question, prove it with the fused labels, then
            // say why the query has nothing to join on.
            VStack(alignment: .leading, spacing: 6) {
                Text("“How much meeting time across all projects?”")
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 4) {
                    ForEach(walkthrough.fusedExamples, id: \.self) { label in
                        TagPill(key: label.key, value: label.value,
                                color: WalkthroughModel.color(key: label.key,
                                                              value: label.value))
                    }
                }
                Text("These meetings sit greyed in the charts — fused inside work:, where type: meeting can't match them.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .driftingKeys:
            let pct = Int((walkthrough.missingSeconds(for: "repo")
                / max(walkthrough.weekTotalSeconds, 1) * 100).rounded())
            Text("You queried repo: — but \(pct)% of your time was accidentally labelled proj:. It rides along here greyed out as missing time; the real History tab would simply drop it.")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text(smell.sideEffect)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func smellCard(_ smell: WalkthroughModel.SchemaSmell) -> some View {
        let active = walkthrough.activeSmell == smell
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                // Radio semantics: one corruption at a time reads cleanly.
                walkthrough.activeSmell = active ? nil : smell
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(smell.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Image(systemName: active
                          ? "exclamationmark.triangle.fill" : "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(active ? AnyShapeStyle(.red)
                                                : AnyShapeStyle(.quaternary))
                }
                Text(smell.symptom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !smell.examples.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(smell.examples, id: \.label) { example in
                            HStack(spacing: 3) {
                                Image(systemName: example.good ? "checkmark" : "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(example.good
                                                     ? AnyShapeStyle(.green)
                                                     : AnyShapeStyle(.red))
                                Text(example.label)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                (Text("Fix  ").foregroundStyle(.tint).bold()
                    + Text(smell.fix))
                    .font(.caption)
            }
            .multilineTextAlignment(.leading)
            .padding(10)
            .padding(.leading, 5)
            .contentShape(Rectangle())
            .background(.quinary)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.red.opacity(active ? 0.9 : 0.3))
                    .frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.red.opacity(active ? 0.5 : 0)))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// MARK: - Page 5: pick your starting label sets

/// One way people run PrimeTime — a card on page 5, and (once the user
/// creates its set) a quick-label suggestion on page 6. File-scoped because
/// both pages read the catalogue.
private struct WalkthroughPersona: Identifiable {
    let name: String
    let symbol: String
    /// The two primary keys, with example values — hints, never
    /// prefilled. (The work *type* is deliberately absent: that's a
    /// quick label's job, not a set's — see the next page.)
    let rows: [(key: String, example: String)]
    /// The example set name woven into the editor's prompt — Tab in the
    /// empty name field accepts it verbatim.
    let nameExample: String
    /// Page 6's suggested quick labels — three values under the one
    /// conventional key `type:`, the kinds of work within this set.
    let quickValues: [String]
    var id: String { name }

    /// The editor's name-field prompt: a directive nudge toward a readable,
    /// chart-legend-friendly set name, phrased around the example labels.
    var nameHint: String { "Pick something readable like \(nameExample)" }

    /// The conventional quick-label key — adopted outright on page 6.
    static let quickKey = "type"

    static let all: [WalkthroughPersona] = [
        WalkthroughPersona(name: "Programming", symbol: "chevron.left.forwardslash.chevron.right",
                           rows: [("repo", "sfi/sfi-website"),
                                  ("feat", "kb-knowledge-graph")],
                           nameExample: "SFI Knowledge Graph",
                           quickValues: ["programming", "review", "planning"]),
        WalkthroughPersona(name: "Studying", symbol: "graduationcap",
                           rows: [("course", "linear-algebra"),
                                  ("topic", "eigenvalues")],
                           nameExample: "Linear Algebra",
                           quickValues: ["lecture", "homework", "revision"]),
        WalkthroughPersona(name: "Reading", symbol: "book",
                           rows: [("book", "locke-lamora"),
                                  ("author", "scott-lynch")],
                           nameExample: "Locke Lamora",
                           quickValues: ["reading", "notes", "research"]),
        WalkthroughPersona(name: "Small Business", symbol: "storefront",
                           rows: [("project", "t-shirt-run"),
                                  ("client", "sfi")],
                           nameExample: "T-Shirt Run",
                           quickValues: ["design", "production", "sales"]),
        WalkthroughPersona(name: "Creative Work", symbol: "paintbrush",
                           rows: [("medium", "digital"),
                                  ("title", "clockwork")],
                           nameExample: "Clockwork",
                           quickValues: ["draft", "refine", "publish"]),
        WalkthroughPersona(name: "Music Production", symbol: "music.note",
                           rows: [("project", "hit-the-lights"),
                                  ("genre", "deep")],
                           nameExample: "Hit the Lights",
                           quickValues: ["composing", "mixing", "mastering"]),
        WalkthroughPersona(name: "Project Management", symbol: "checklist",
                           rows: [("project", "q3-roadmap"),
                                  ("meeting", "sprint-planning")],
                           nameExample: "Q3 Roadmap",
                           quickValues: ["planning", "review", "standup"]),
        WalkthroughPersona(name: "Dungeon Master", symbol: "die.face.6",
                           rows: [("encounter", "temporal-paradox"),
                                  ("repo", "sfi/prime-campaigns")],
                           nameExample: "Prime Campaigns",
                           quickValues: ["prep", "session", "worldbuilding"]),
    ]

    static func named(_ id: String) -> WalkthroughPersona? {
        all.first { $0.id == id }
    }
}

/// The eight personas of the catalogue above, each openable into a small
/// editor that creates a *real* label set — the walkthrough's one page
/// that writes into the user's data, because that's its whole point.
private struct LabelSetsPage: View {
    @Environment(AppModel.self) private var model
    @Bindable var walkthrough: WalkthroughModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Persona = WalkthroughPersona

    /// The grid's rows, two cards per row.
    private static let personaPairs: [[Persona]] =
        stride(from: 0, to: Persona.all.count, by: 2).map {
            Array(Persona.all[$0..<min($0 + 2, Persona.all.count)])
        }

    /// One editable label row in the persona editor — the popover editor's
    /// key/value rows plus a colour swatch, with the persona's example as
    /// placeholder on seeded rows.
    private struct DraftRow: Identifiable {
        let id = UUID()
        var key: String
        var value: String
        var color: Color
        var example: String?

        var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }
        var trimmedValue: String { value.trimmingCharacters(in: .whitespaces) }
        var incomplete: Bool { trimmedKey.isEmpty || trimmedValue.isEmpty }
    }

    @State private var editing: Persona?
    /// Tallest card in the grid — every card takes it as a floor, so a card
    /// whose pills fit one line (Reading, Creative Work) doesn't run shorter
    /// than its neighbours; its content centres in the extra room.
    @State private var cardHeight: CGFloat = 0
    @State private var draftName = ""
    @State private var draftRows: [DraftRow] = []
    /// Rows flagged by a failed add — their empty fields stay outlined red
    /// until filled. No "required" copy anywhere, per the review.
    @State private var invalidRows: Set<UUID> = []
    /// Failed-add counter; each bump drives one shake of the add button.
    @State private var shakes = 0

    /// Personas whose set the user already created — from the shared model,
    /// so the checkmarks survive paging away and back.
    private var added: Set<String> {
        Set(walkthrough.createdSets.map(\.personaID))
    }

    var body: some View {
        WalkthroughPage(index: 4, title: "Pick your starting Label Sets",
                        subtitle: "Eight ways people run PrimeTime. Open one, type your own values, and it becomes a real one-click set.") {
            Group {
                if let persona = editing {
                    editor(for: persona)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        // Deliberately not a LazyVGrid: lazy cells materialise
                        // mid page-slide, so the cards visibly popped in while
                        // the text was still moving.
                        ForEach(Array(Self.personaPairs.enumerated()),
                                id: \.offset) { _, pair in
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(pair) { persona in
                                    card(for: persona)
                                        .frame(maxWidth: .infinity)
                                }
                                if pair.count == 1 {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                            // Cards whose pills fit one line would otherwise
                            // run shorter than their neighbour: the row takes
                            // the taller card's height, the shorter one
                            // stretches to match (content centres, below).
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Add as many as fit — or none. The Label Sets tab can do all of this later.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: editing?.id)
        }
    }

    private func card(for persona: Persona) -> some View {
        let isAdded = added.contains(persona.id)
        return Button {
            open(persona)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: persona.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(persona.name).font(.body.weight(.medium))
                    // Fixed gap, top-aligned: a one-line chip row lines up
                    // with the *first* chip row of a two-line neighbour, and
                    // the card's extra height simply trails below.
                    FlowLayout(spacing: 4) {
                        ForEach(persona.rows, id: \.key) { row in
                            TagPill(key: row.key, value: row.example,
                                    color: WalkthroughModel.color(key: row.key,
                                                                  value: row.example))
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAdded ? AnyShapeStyle(.green)
                                             : AnyShapeStyle(.quaternary))
            }
            .padding(10)
            // Fill whatever height the row settled on — and at least the
            // grid's tallest card.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .frame(minHeight: cardHeight > 0 ? cardHeight : nil)
            .contentShape(Rectangle())
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .overlay {
            GeometryReader { proxy in
                Color.clear.preference(key: CardHeightKey.self,
                                       value: proxy.size.height)
            }
        }
        .onPreferenceChange(CardHeightKey.self) { cardHeight = max(cardHeight, $0) }
    }

    private func open(_ persona: Persona) {
        // The name starts blank on purpose: the prompt is a directive hint
        // ("Pick something readable like …"), and Add stays disabled until
        // the user names the set themselves.
        draftName = ""
        // Swatches start on the walkthrough's colour for the example, so the
        // editor matches the card the user just clicked.
        draftRows = persona.rows.map {
            DraftRow(key: $0.key, value: "",
                     color: WalkthroughModel.color(key: $0.key, value: $0.example),
                     example: $0.example)
        }
        invalidRows = []
        editing = persona
    }

    /// The persona editor: the popover's editable key/value rows (add,
    /// remove, retype — the seeded keys are suggestions, not law) with a
    /// colour swatch per row.
    private func editor(for persona: Persona) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: persona.symbol)
                    .foregroundStyle(.tint)
                TextField("Set name", text: $draftName,
                          prompt: Text(persona.nameHint))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.medium))
                    // Tab completes the prompt's example while the field is
                    // empty; once anything is typed it tabs on as usual.
                    .onKeyPress(.tab) {
                        guard draftName.trimmingCharacters(in: .whitespaces).isEmpty
                        else { return .ignored }
                        draftName = persona.nameExample
                        return .handled
                    }
            }
            ForEach($draftRows) { $row in
                HStack(spacing: 6) {
                    ColorPicker("", selection: $row.color, supportsOpacity: false)
                        .labelsHidden()
                    TextField("key", text: $row.key)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .frame(width: LabelEditorStyle.keyFieldWidth)
                        .overlay(invalidOutline(flagged(row) && row.trimmedKey.isEmpty))
                    Text(":").foregroundStyle(.secondary)
                    TextField("value", text: $row.value,
                              prompt: row.example.map { Text($0) })
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .overlay(invalidOutline(flagged(row) && row.trimmedValue.isEmpty))
                        .onKeyPress(.tab) {
                            guard row.trimmedValue.isEmpty, let example = row.example
                            else { return .ignored }
                            row.value = example
                            return .handled
                        }
                    Button(role: .destructive) {
                        // Read the id before removeAll — reading the `row`
                        // binding inside the predicate re-enters the array's
                        // exclusive access and traps.
                        let id = row.id
                        draftRows.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                draftRows.append(DraftRow(key: "", value: "",
                                          color: WalkthroughModel.keyColor("")))
            } label: {
                Label("Add Label", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Text("The grey values are examples — type your own, or press Tab to keep one.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("Cancel") { editing = nil }
                Button("Add label set") { add(persona) }
                    .buttonStyle(.borderedProminent)
                    .tint(anyFlagged ? .red : nil)
                    .modifier(Shake(animatableData: CGFloat(shakes)))
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// A field flagged by a failed add keeps its outline only while still
    /// empty — typing clears it, without any bookkeeping.
    private func flagged(_ row: DraftRow) -> Bool {
        invalidRows.contains(row.id)
    }

    private var anyFlagged: Bool {
        draftRows.contains { flagged($0) && $0.incomplete }
    }

    private func invalidOutline(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(.red, lineWidth: 1)
            .opacity(on ? 1 : 0)
    }

    /// Create the real set — or refuse: a blank key or value doesn't pass.
    /// The refusal is shown, not written: the empty fields outline red and
    /// the add button shakes. Chosen colours go through the model's
    /// per-value colour store; duplicate names are skipped (the set already
    /// exists — still counts as added).
    private func add(_ persona: Persona) {
        let incomplete = draftRows.filter(\.incomplete)
        guard incomplete.isEmpty, !draftRows.isEmpty else {
            invalidRows.formUnion(incomplete.map(\.id))
            if reduceMotion {
                shakes += 1   // unanimated: the red tint still lands
            } else {
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
            return
        }
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let set: TagSet
        if let existing = model.tagSets.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) {
            set = existing   // the set already exists — still counts as added
        } else {
            var tags: [TagRow] = []
            for row in draftRows {
                tags.append(TagRow(key: row.trimmedKey, value: row.trimmedValue))
                model.setValueColor(key: row.trimmedKey, value: row.trimmedValue,
                                    color: row.color)
            }
            set = TagSet(name: name, tags: tags, symbolName: persona.symbol)
            model.tagSets.append(set)
        }
        if !walkthrough.createdSets.contains(where: { $0.setID == set.id }) {
            walkthrough.createdSets.append(
                WalkthroughModel.CreatedSet(setID: set.id, personaID: persona.id))
        }
        editing = nil
    }
}

/// The tallest persona card's height (see `LabelSetsPage.cardHeight`).
private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Horizontal shake for a refused action — driven by an incrementing
/// counter; each whole step sweeps three cycles and lands back at rest.
private struct Shake: GeometryEffect {
    var travel: CGFloat = 5
    var cycles: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * cycles * 2), y: 0))
    }
}

// MARK: - Page 6: quick labels

private struct QuickLabelsPage: View {
    @Environment(AppModel.self) private var model
    @Bindable var walkthrough: WalkthroughModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Quick: Hashable {
        let key: String
        let value: String
    }

    /// The mocked set — the SWE-shop scheme's own labels — and its quick
    /// labels: three work types that swap with each other, exactly the
    /// role page 5 kept *out* of the sets.
    private static let base = [Quick(key: "repo", value: "primetime"),
                               Quick(key: "feat", value: "onboarding")]
    private static let quicks = [Quick(key: "type", value: "programming"),
                                 Quick(key: "type", value: "review"),
                                 Quick(key: "type", value: "planning")]

    /// The example widget's chip colours — blue, gold, purple — inherited by
    /// position, so every persona's three suggested values read as instances
    /// of the example. Written into the user's palette when a suggestion is
    /// added, so the real chips keep the hue.
    private static func suggestionColor(at index: Int) -> Color {
        let quick = quicks[index % quicks.count]
        return WalkthroughModel.color(key: quick.key, value: quick.value)
    }

    @State private var applied: Quick?

    /// A set the user created on page 5, joined with its persona — the
    /// source of that set's three suggested `type:` quick labels.
    private struct Suggestion: Identifiable {
        let tagSet: TagSet
        let persona: WalkthroughPersona
        var id: UUID { tagSet.id }
    }

    private var anim: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    /// The sets created on page 5 that still exist, in creation order.
    private var suggestions: [Suggestion] {
        walkthrough.createdSets.compactMap { created in
            guard let set = model.tagSets.first(where: { $0.id == created.setID }),
                  let persona = WalkthroughPersona.named(created.personaID)
            else { return nil }
            return Suggestion(tagSet: set, persona: persona)
        }
    }

    var body: some View {
        WalkthroughPage(index: 5, title: "Quick labels",
                        subtitle: "Often you want to start from a label set but add one more label — the work type, the client. PrimeTime lets you define these Quick Labels ahead of time, so switching contexts takes a couple of clicks.") {
            VStack(alignment: .leading, spacing: 14) {
                if suggestions.isEmpty {
                    // Alone, the card must not stretch to the page: cap it
                    // at its ideal height (both cards are maxHeight-flexible
                    // for the equal-height row below).
                    mockRow
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Two equal-width cards, centred with air on both sides.
                    // fixedSize caps the row at the taller card's ideal
                    // height, and each card stretches to match.
                    HStack(alignment: .top, spacing: 52) {
                        mockRow
                            .frame(width: 280)
                        suggestionsCard
                            .frame(width: 280)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                preview
                Text("All three quick labels share the key type:, so they swap with each other — click between them as often as you like. Clicking the row anywhere else starts from just the set's own labels. A set can even be quick labels only — no baked-in labels at all — which makes a tidy home for hobbies: game:, book:, activity:.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: suggestions.isEmpty ? 440 : 660)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: Suggested quick labels for the user's own sets

    /// The sets created on page 5, each with three suggested quick labels
    /// under the conventional key `type:` — the kinds of work within the
    /// set. All or nothing: the chips are a preview, and the one button
    /// adds every remaining suggestion verbatim to the user's real per-set
    /// quick labels, like page 5 wrote real sets.
    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested for your sets")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: suggestion.tagSet.symbol)
                            .font(.caption)
                            .foregroundStyle(.tint)
                        Text(suggestion.tagSet.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    FlowLayout(spacing: 4) {
                        ForEach(Array(suggestion.persona.quickValues.enumerated()),
                                id: \.element) { index, value in
                            suggestionChip(value, at: index, for: suggestion.tagSet)
                        }
                    }
                }
            }
            Text("You customize these any time in the Label Sets menu.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Add suggested quick labels", action: addAllSuggestions)
                .buttonStyle(GoldenSparkleButtonStyle())
                .disabled(allSuggestionsAdded)
                .pointingHandCursor()
                .frame(maxWidth: .infinity)
        }
        // Flexible height so the side-by-side layout can stretch this card
        // to the quick-start card's height; the Spacer above keeps the
        // button pinned to the bottom edge when it does.
        .frame(maxHeight: .infinity)
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Whether this exact suggestion already sits in the set's quick labels
    /// (added here, or defined before onboarding).
    private func isAdded(_ value: String, in set: TagSet) -> Bool {
        model.quickLabels(for: set).contains {
            normalizeKey($0.key) == WalkthroughPersona.quickKey
                && $0.value.trimmingCharacters(in: .whitespaces) == value
        }
    }

    private var allSuggestionsAdded: Bool {
        suggestions.allSatisfy { suggestion in
            suggestion.persona.quickValues.allSatisfy { isAdded($0, in: suggestion.tagSet) }
        }
    }

    /// A suggested chip — a preview, not a control: the card is all or
    /// nothing, added by the one button below. Pending chips wear the
    /// example's positional colour outlined; added ones render filled from
    /// the user's real palette (which the add seeded with that colour).
    private func suggestionChip(_ value: String, at index: Int,
                                for set: TagSet) -> some View {
        let added = isAdded(value, in: set)
        let color = added ? model.tagColor(for: WalkthroughPersona.quickKey, value: value)
                          : Self.suggestionColor(at: index)
        return Text("+\(value)")
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(added ? AnyShapeStyle(color.contrastingTextColor)
                                   : AnyShapeStyle(.primary))
            .background(Capsule().fill(added ? color : .clear))
            .overlay(Capsule().strokeBorder(added ? .clear : color))
    }

    /// The card's one-click path: every suggestion not already present,
    /// added verbatim.
    private func addAllSuggestions() {
        withAnimation(anim) {
            for suggestion in suggestions {
                for (index, value) in suggestion.persona.quickValues.enumerated()
                where !isAdded(value, in: suggestion.tagSet) {
                    // Carry the chips' positional colours into the palette —
                    // without clobbering a pair the user already coloured.
                    if model.valueColor(key: WalkthroughPersona.quickKey,
                                        value: value) == nil {
                        model.setValueColor(key: WalkthroughPersona.quickKey,
                                            value: value,
                                            color: Self.suggestionColor(at: index))
                    }
                    model.quickLabels[suggestion.tagSet.id.uuidString, default: []]
                        .append(TagRow(key: WalkthroughPersona.quickKey, value: value))
                }
            }
        }
    }

    /// A quick-start row like the popover's, chips permanently revealed (the
    /// real row shows them on hover). As in the popover, the row itself is
    /// the click target for "just the set" — anywhere that isn't a chip.
    private var mockRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick start")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Stretched beside the suggestions card the widget would hug
            // the top-left corner — centre it in the card's free space.
            Spacer(minLength: 6)
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    applied = nil
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PrimeTime")
                        .font(.callout)
                    FlowLayout(spacing: 4) {
                        ForEach(Self.base, id: \.self) { tag in
                            TagPill(key: tag.key, value: tag.value,
                                    color: WalkthroughModel.color(key: tag.key, value: tag.value))
                        }
                    }
                    FlowLayout(spacing: 4) {
                        ForEach(Self.quicks, id: \.self) { quick in
                            chip(quick)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Start with the set's labels")
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        // Flexible on both axes so the side-by-side layout can stretch this
        // card to the suggestions card's height and the row's width.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Chips apply, they never toggle off — like the popover, where a chip
    /// always means "start with this"; the row body is the way back to the
    /// set's plain labels. So switching types is endlessly repeatable.
    private func chip(_ quick: Quick) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                applied = quick
            }
        } label: {
            Text("+\(quick.value)")
        }
        .buttonStyle(QuickLabelChipStyle(
            color: WalkthroughModel.color(key: quick.key, value: quick.value),
            filled: applied == quick))
        .pointingHandCursor()
        .help("Start with \(quick.key): \(quick.value)")
    }

    /// The span a click would start: the set's labels with same-key
    /// replacement applied — the `TagSet.labels(applying:)` rule, computed
    /// locally on the mock data.
    @ViewBuilder
    private var preview: some View {
        let labels = applied.map { quick in
            Self.base.filter { $0.key != quick.key } + [quick]
        } ?? Self.base
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("One click starts:")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(labels, id: \.self) { tag in
                    TagPill(key: tag.key, value: tag.value,
                            color: WalkthroughModel.color(key: tag.key, value: tag.value))
                }
            }
        }
        .padding(.top, 16)
    }
}

/// The suggestions card's call to action: quiet at rest, gilded on
/// mouse-over — a torch-gold border, tinted fill, and a bouncing sparkle,
/// echoing the popover quick labels' hover flourish.
private struct GoldenSparkleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var highlighted: Bool { hovering && isEnabled }

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .foregroundStyle(highlighted ? AnyShapeStyle(Brand.torchGold)
                                                 : AnyShapeStyle(.secondary))
                    .symbolEffect(.bounce, value: reduceMotion ? false : highlighted)
                configuration.label
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Brand.torchGold.opacity(highlighted ? 0.14 : 0)))
            .overlay(Capsule().strokeBorder(
                highlighted ? Brand.torchGold : Color.secondary.opacity(0.4),
                lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: highlighted)
        }
    }
}

// MARK: - Page 7: where things live

private struct SurfacesPage: View {
    private struct Surface: Identifiable {
        let symbol: String
        let name: String
        let blurb: String
        var id: String { name }
    }

    // Blurbs mirror the website/readme feature copy.
    private static let surfaces: [Surface] = [
        Surface(symbol: "timer", name: "Menu-bar popover",
                blurb: "Start and stop timers, add notes or change labels on the fly."),
        Surface(symbol: "square.grid.2x2", name: "Launcher",
                blurb: "Saved label sets as one-click cards — icons and colors for the way you actually organize work. Sets that are already running light up."),
        Surface(symbol: "tag", name: "Label Sets",
                blurb: "Name and edit the sets behind one-click timers. Set up quick labels to fit your workflow."),
        Surface(symbol: "list.bullet.rectangle", name: "Log",
                blurb: "Review and freely edit timespans after-the-fact: because real work overlaps, gets interrupted, and needs correcting."),
        Surface(symbol: "calendar", name: "Calendar",
                blurb: "Your week laid out hour by hour. Overlapping timers share columns, so multi-tasking is visible instead of hidden."),
        Surface(symbol: "chart.pie", name: "History",
                blurb: "Visualize your timespans with group-by based aggregations."),
        Surface(symbol: "stethoscope", name: "Label Review",
                blurb: "Merge drifted keys and stray values. With PrimeTime it's easy to catch these outliers and correct them before they impact downstream."),
        Surface(symbol: "gear", name: "Settings",
                blurb: "Sync, colours, and everything else."),
    ]

    var body: some View {
        WalkthroughPage(index: 6, title: "Where things live",
                        subtitle: "Everything you just did in miniature has a real surface in the app.") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Self.surfaces) { surface in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: surface.symbol)
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                        Text(surface.name)
                            .font(.callout.weight(.semibold))
                            .frame(width: 130, alignment: .leading)
                        Text(surface.blurb)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Link(destination: URL(string: "https://primetime.tools/docs/labels")!) {
                    Label("Read the full labelling guide", systemImage: "book")
                }
                .font(.callout)
                .padding(.top, 6)
                Text("Hit Continue to finish — you'll land in the Label Sets tab, next to whatever you just created.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
