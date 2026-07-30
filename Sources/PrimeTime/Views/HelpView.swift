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
                Divider()
                Text("PrimeTime \(Self.versionString)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
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
