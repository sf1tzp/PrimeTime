import SwiftUI

/// The Help tab: static copy explaining the data model and each surface of
/// the app. The subtleties documented here (key/value split, server-vs-local
/// colours, tag sets as launch presets, review rewrites bounded by the scan)
/// otherwise live only in code comments — keep the sections short and cheap
/// to amend as features change.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(HelpSection.all) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(section.title, systemImage: section.symbol)
                            .font(.headline)
                        // .init so the string is parsed as markdown.
                        Text(.init(section.body))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if section.id != HelpSection.all.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }
}

private struct HelpSection: Identifiable {
    let title: String
    let symbol: String
    let body: String   // inline markdown; \n\n separates paragraphs
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

            Tag **keys** live on the Traggo server, each with a colour — recolouring a \
            key changes it everywhere the key appears, including the web UI. With \
            *Colour tags by value* on (see Settings), you can additionally pick a colour \
            per key: value pair; those overrides are stored on this Mac only.

            **Tag sets** are named bundles of tags used to start timespans with one \
            click, with a name and an icon. They're a convenience stored on this Mac, \
            not a server concept: a timespan started from a set keeps the tags but no \
            link to the set. Their order matters — the popover lists the first few, in \
            order (drag to reorder in Tag Sets).
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
            showing the icon picked in Tag Sets. Click to start the set; a card whose \
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
            title: "Tag Review",
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
            Server URL, device name (how this Mac appears under Traggo's devices), and \
            the signed-in account. **Quick-start tag sets** caps how many sets the \
            popover lists (0 shows all). **Colour tags by value** enables the per-Mac \
            key: value colour overrides described above.
            """),
    ]
}
