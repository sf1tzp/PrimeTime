import SwiftUI

/// The Help tab: static copy explaining the data model and each surface of
/// the app, one collapsible card per section (first card open by default).
/// The subtleties documented here (key/value split, server-vs-local colours,
/// tag sets as launch presets, review rewrites bounded by the scan) otherwise
/// live only in code comments — keep the sections short and cheap to amend as
/// features change.
struct HelpView: View {
    @State private var expanded: Set<String> = [HelpSection.all[0].id]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(HelpSection.all) { section in
                    HelpSectionCard(section: section, isExpanded: binding(for: section))
                }
                Text("PrimeTime \(Self.versionString)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }

    private func binding(for section: HelpSection) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(section.id) },
            set: { open in
                if open { expanded.insert(section.id) } else { expanded.remove(section.id) }
            })
    }

    /// "1.2.0 (347)" from the bundle's Info.plist; a bare SwiftPM binary
    /// (`just run-dev`) has no bundle metadata and reads "dev".
    private static var versionString: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return "dev" }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

/// One section as a card: a full-width clickable header (icon, title,
/// chevron) over the body, which is paragraphs — optionally interleaved with
/// a numbered rule list — shown only while expanded.
private struct HelpSectionCard: View {
    let section: HelpSection
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: section.symbol)
                        .frame(width: 20)
                        .foregroundStyle(.tint)
                    Text(section.title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    paragraphs(of: section.body)
                    if !section.rules.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(section.rules.enumerated()), id: \.offset) { index, rule in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.heading)
                                            .font(.callout.weight(.semibold))
                                        bodyText(rule.detail)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if let footer = section.footer {
                        paragraphs(of: footer)
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 28)  // align body under the title, past the icon
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func paragraphs(of text: String) -> some View {
        ForEach(text.components(separatedBy: "\n\n"), id: \.self) { paragraph in
            bodyText(paragraph)
        }
    }

    /// `.init` so the string is parsed as markdown.
    private func bodyText(_ markdown: String) -> some View {
        Text(.init(markdown))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpSection: Identifiable {
    struct Rule {
        let heading: String
        let detail: String   // inline markdown
    }

    let title: String
    let symbol: String
    let body: String         // inline markdown; \n\n separates paragraphs
    var rules: [Rule] = []   // numbered list rendered between body and footer
    var footer: String? = nil
    var id: String { title }

    static let all: [HelpSection] = [
        HelpSection(
            title: "The data model",
            symbol: "cube",
            body: """
            Time is tracked as **timespans**: a start, an end, an optional note, and any \
            number of tags. A *running* timespan is one with no end yet — the menu-bar \
            clock counts it up. Overlaps are allowed, so several can run at once.

            A tag is a **key: value** pair on a timespan, like `project: traggo`. Values \
            are free text; keys are lower-cased with spaces turned into “-”.

            Tag **keys** each carry a colour, stored with your timespans in the local \
            database; recolouring a key changes it everywhere the key appears. *Colour \
            tags by value* (on by default; see Settings) additionally lets you pick a \
            colour per key: value pair, so spans differ by what they're about rather \
            than only by key.

            **Label sets** are named bundles of tags used to start timespans with one \
            click, with a name and an icon. A timespan started from a set keeps the \
            tags but no link to the set. Their order matters — the popover lists the \
            first few, in order (drag to reorder in Label Sets).

            Everything above lives on this Mac by default. Connect a **sync server** \
            (see Settings) and it becomes yours-across-machines instead: timespans, \
            key and value colours, tag sets, and the two settings below all follow \
            your account to every connected Mac.
            """),
        HelpSection(
            title: "Choosing good tags",
            symbol: "tag",
            body: """
            Tags are the whole query model — every History chart, export filter, and \
            Label Review pass works over the keys and values you pick, so the schema \
            is worth a minute of thought. Six rules cover it:
            """,
            rules: [
                Rule(
                    heading: "Tag what you'll query by",
                    detail: """
                    If you'd never group a chart or filter an export by it, it isn't \
                    a tag — put it in the note.
                    """),
                Rule(
                    heading: "Keep values from a small, stable vocabulary",
                    detail: """
                    Every distinct value is one more slice in every chart that groups \
                    by its key; one-off values (ticket titles, prose) turn a report \
                    back into a log.
                    """),
                Rule(
                    heading: "One fact per key",
                    detail: """
                    `repo`, `feature`, and `type` as three keys filter and join \
                    independently; welded into one value they can only match whole.
                    """),
                Rule(
                    heading: "Pick key names once",
                    detail: """
                    `proj` on Mondays and `project` on Thursdays splits your history \
                    in two — every total silently misses whichever spelling you forget.
                    """),
                Rule(
                    heading: "Mirror systems you'll join against",
                    detail: """
                    To line time up with source control, use the forge's exact naming \
                    (`repo: sfi/PrimeTime`, not `repo: primetime`) — joins are literal.
                    """),
                Rule(
                    heading: "Decide what untagged means",
                    detail: """
                    A span with no `client` should mean something on purpose \
                    (internal? unbilled?), so gaps carry information instead of doubt.
                    """),
            ],
            footer: """
            A starter schema that covers most work: `repo: sfi/PrimeTime`, \
            `feat: label-review`, `type: review`, `client: acme` — hours per client, \
            review share per repo, and span-to-PR joins, with no hierarchy decided up \
            front. Start smaller if in doubt: a key is easy to add and painful to \
            rename (though Label Review can rescue a drifted schema after the fact).

            The full guide, with worked examples of schemas going wrong, is at \
            [primetime.tools/docs/labels](https://primetime.tools/docs/labels).
            """),
        HelpSection(
            title: "Menu bar popover",
            symbol: "menubar.arrow.up.rectangle",
            body: """
            The top section lists every **running timespan**: elapsed time, tags, a \
            pencil that edits its tags and note in place, and a square stop button. \
            **Start blank timer** begins an untagged timespan — alongside anything \
            already running — and opens its editor so you can describe the time while \
            it runs.

            **Quick start** shows your tag sets, capped to the first N (set the cap in \
            Settings; “N more…” opens the Launcher). A set whose exact tags are \
            currently running is hidden until that timespan stops. While a timer runs \
            the other rows grey out, but each keeps an enabled **＋** that starts the \
            set *alongside* the running timer.
            """),
        HelpSection(
            title: "Launcher",
            symbol: "square.grid.2x2",
            body: """
            Every tag set as a clickable card — tinted with its first tag's colour and \
            showing the icon picked in Label Sets. Click to start the set; a card whose \
            set is currently running is dimmed until it stops (other cards keep \
            working, since timespans may overlap). The dashed **＋** card creates a new \
            tag set.
            """),
        HelpSection(
            title: "Log",
            symbol: "list.bullet.rectangle",
            body: """
            The week's timespans, day by day. Click a row to edit in place — start and \
            end (the arrows step by the minute), tags, note — or delete it.

            A row whose tag combination matches no saved tag set shows a **＋**: it \
            saves those tags as a new set, so an ad-hoc timespan you keep repeating is \
            one click from becoming a preset.
            """),
        HelpSection(
            title: "Calendar",
            symbol: "calendar",
            body: """
            The same week as a time grid, timespans as coloured blocks (overlapping \
            spans share the column; spans crossing midnight draw one block per day). \
            Click a block to edit it in a popover.
            """),
        HelpSection(
            title: "History",
            symbol: "chart.pie",
            body: """
            Two donut charts, each with its own **Group by**: a tag key (one slice per \
            value) or a tag set (one slice per member tag), so two breakdowns of the \
            same week sit side by side. The bars below show each day — one stack per \
            donut when both are active.

            Chart colours come from a fixed palette; with *Colour tags by value* on, \
            your per-value colours win so the charts match the pills elsewhere.
            """),
        HelpSection(
            title: "Label Review",
            symbol: "stethoscope",
            body: """
            Scans your timespans (pick how far back) and lists every tag key with its \
            values and usage counts — the keys with the most distinct values first, \
            which is where typos, near-duplicates, and casing drift show up.

            Cleanups are **staged, not immediate**. Rename a key or value from its \
            pencil; drag a value onto another key to move it there; expand a value and \
            shift-click instances to drag just a subset. Staged changes collect at the \
            bottom as red→green sentences where the target spelling stays editable. \
            **Approve Changes** then rewrites the affected timespans one by one, with \
            progress and cancel.

            Two boundaries to know: rewrites only touch the **scanned range** — spans \
            outside it keep their old tags (scan wider to catch them; approving again \
            after a failure or cancel safely picks up where it left off) — and \
            **running timespans are never rewritten**; stop them first, then rescan.
            """),
        HelpSection(
            title: "Settings",
            symbol: "gear",
            body: """
            **Storage** is a local database on this Mac — the default needs no server \
            and no account. **Sync** optionally connects a sync server: sign in once \
            and this Mac gets a device token (revocable server-side; your password is \
            never stored). From then on every change — starting and stopping \
            timespans, edits, colours, tag sets, the settings below — lands locally \
            first and syncs in the background, so nothing waits on the network and \
            offline edits catch up on reconnect. If the same thing was edited on two \
            Macs, the most recent edit wins. **Import from Traggo** copies an existing \
            Traggo server's history into the local database (safe to re-run).

            **Quick-start tag sets** caps how many sets the popover lists (0 shows \
            all). **Colour tags by value** (on by default) enables the per-pair colour \
            overrides described above; turn it off to colour strictly by key. With a \
            sync server connected, both follow your account across Macs.
            """),
    ]
}
