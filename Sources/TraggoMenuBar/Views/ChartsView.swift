import SwiftUI
import Charts

/// The History tab: a donut + totals breakdown and a daily stacked bar chart
/// for the displayed week. Instead of the web UI's build-your-own dashboards,
/// flexibility lives in one control: group by any tag key, or by a Tag Set
/// (one series per member tag).
struct HistoryChartsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let history = model.history
        VStack(spacing: 0) {
            WeekNavigatorView()
            Divider()
            controls
            Divider()

            if let error = history.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(6)
            }

            if let grouping = history.chartGrouping {
                let totals = folded(history.totals(for: grouping))
                if totals.isEmpty {
                    emptyState
                } else {
                    charts(grouping: grouping, totals: totals)
                }
            } else {
                emptyState
            }
        }
        .task {
            await history.loadIfNeeded()
            if history.chartGrouping == nil {
                history.chartGrouping = history.defaultGrouping()
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        @Bindable var history = model.history
        return HStack {
            Picker("Group by", selection: $history.chartGrouping) {
                Section("Tag keys") {
                    ForEach(model.history.groupableKeys, id: \.self) { key in
                        Text(key).tag(ChartGrouping?.some(.key(key)))
                    }
                }
                let sets = model.tagSets.filter { !$0.wireTags.isEmpty }
                if !sets.isEmpty {
                    Section("Tag sets") {
                        ForEach(sets) { set in
                            Text(set.name.isEmpty ? "Untitled" : set.name)
                                .tag(ChartGrouping?.some(.tagSet(set.id)))
                        }
                    }
                }
            }
            .fixedSize()

            Spacer()

            Text("Total \(formatDuration(model.history.weekTotalSeconds))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Charts

    private func charts(grouping: ChartGrouping, totals: [SeriesTotal]) -> some View {
        let colors = colorMap(for: totals, grouping: grouping)
        let daily = foldedDaily(model.history.dailyTotals(for: grouping),
                                keeping: Set(totals.map(\.label)))
        let grand = totals.reduce(0) { $0 + $1.seconds }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 24) {
                    donut(totals: totals, colors: colors, grand: grand)
                    breakdownList(totals: totals, colors: colors, grand: grand)
                    // Trailing space is deliberately left empty: reserved for
                    // future content next to the breakdown.
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)

                Text("Per day")
                    .font(.subheadline.weight(.semibold))
                dailyChart(daily, colors: colors, seriesOrder: totals.map(\.label))
            }
            .padding(12)
            .padding(.bottom, 12)
        }
    }

    private func donut(totals: [SeriesTotal], colors: [String: Color], grand: TimeInterval) -> some View {
        Chart(totals) { item in
            SectorMark(angle: .value("Time", item.seconds),
                       innerRadius: .ratio(0.62),
                       angularInset: 1.5)
                .foregroundStyle(colors[item.label] ?? .gray)
                .cornerRadius(2)
        }
        .chartLegend(.hidden)   // the breakdown list is the legend
        .frame(width: 160, height: 160)
        .overlay {
            VStack(spacing: 0) {
                Text(formatDuration(grand))
                    .font(.headline.monospacedDigit())
                Text("tracked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func breakdownList(totals: [SeriesTotal], colors: [String: Color], grand: TimeInterval) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            ForEach(totals) { item in
                GridRow {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colors[item.label] ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(item.label)
                            .lineLimit(1)
                    }
                    Text(formatDuration(item.seconds))
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Text(grand > 0
                         ? (item.seconds / grand).formatted(.percent.precision(.fractionLength(0)))
                         : "")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
                .font(.callout)
            }
        }
    }

    private func dailyChart(_ daily: [DailyTotal], colors: [String: Color], seriesOrder: [String]) -> some View {
        // Stack biggest series at the baseline: emit marks in totals order.
        let rank = Dictionary(uniqueKeysWithValues: seriesOrder.enumerated().map { ($1, $0) })
        let ordered = daily.sorted {
            (rank[$0.label] ?? .max, $0.day) < (rank[$1.label] ?? .max, $1.day)
        }
        return Chart(ordered) { item in
            BarMark(x: .value("Day", item.day, unit: .day),
                    y: .value("Hours", item.seconds / 3600))
                .foregroundStyle(colors[item.label] ?? .gray)
                .cornerRadius(2)
        }
        // Pin the domain to the whole week, or a single day of data would
        // stretch its bar across the full plot width.
        .chartXScale(domain: model.history.weekInterval.start...model.history.weekInterval.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                if let hours = value.as(Double.self) {
                    AxisValueLabel {
                        Text("\(hours.formatted(.number.precision(.fractionLength(0...1))))h")
                    }
                }
            }
        }
        .frame(height: 200)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.pie")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No tagged time this week")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Series colours (validated palette, fixed assignment)

    /// A colorblind-validated categorical palette (light/dark variants). Series
    /// are assigned slots by alphabetical label order — stable across weeks and
    /// grouping tweaks, so a series keeps its colour as data changes ("colour
    /// follows the entity, not its rank").
    private var palette: [Color] {
        let hexes = colorScheme == .dark
            ? ["#3987e5", "#199e70", "#c98500", "#008300",
               "#9085e9", "#e66767", "#d55181", "#d95926"]
            : ["#2a78d6", "#1baf7a", "#eda100", "#008300",
               "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"]
        return hexes.compactMap { Color(hex: $0) }
    }

    private func colorMap(for totals: [SeriesTotal], grouping: ChartGrouping) -> [String: Color] {
        let labels = totals.map(\.label).filter { $0 != Self.otherLabel }.sorted()
        var map: [String: Color] = [Self.otherLabel: .gray]
        for (index, label) in labels.enumerated() {
            map[label] = palette[index % palette.count]
        }
        // With "colour by value" on, user-picked overrides beat palette slots
        // so the charts match the tag pills elsewhere in the app.
        if model.colorTagsByValue {
            for label in labels {
                if let override = overrideColor(for: label, grouping: grouping) {
                    map[label] = override
                }
            }
        }
        return map
    }

    /// The user's per-value colour for a series label, if one is set. Labels
    /// are values when grouping by key, "key: value" for tag-set members.
    private func overrideColor(for label: String, grouping: ChartGrouping) -> Color? {
        switch grouping {
        case .key(let key):
            return model.valueColor(key: key, value: label)
        case .tagSet(let id):
            guard let set = model.tagSets.first(where: { $0.id == id }),
                  let tag = set.wireTags.first(where: {
                      ($0.value.isEmpty ? $0.key : "\($0.key): \($0.value)") == label
                  }) else { return nil }
            return model.valueColor(key: tag.key, value: tag.value)
        }
    }

    // MARK: Folding (cap series count, never cycle hues)

    private static let otherLabel = "Other"

    /// Keep the top 7 series; everything else folds into a gray "Other".
    private func folded(_ totals: [SeriesTotal]) -> [SeriesTotal] {
        guard totals.count > 8 else { return totals }
        let kept = totals.prefix(7)
        let rest = totals.dropFirst(7).reduce(0) { $0 + $1.seconds }
        return Array(kept) + [SeriesTotal(label: Self.otherLabel, seconds: rest)]
    }

    private func foldedDaily(_ daily: [DailyTotal], keeping: Set<String>) -> [DailyTotal] {
        var folded: [String: DailyTotal] = [:]  // keyed by day+label
        var result: [DailyTotal] = []
        for item in daily {
            if keeping.contains(item.label) {
                result.append(item)
            } else {
                let key = "\(item.day.timeIntervalSince1970)"
                let existing = folded[key]?.seconds ?? 0
                folded[key] = DailyTotal(day: item.day, label: Self.otherLabel,
                                         seconds: existing + item.seconds)
            }
        }
        return result + folded.values.sorted { $0.day < $1.day }
    }
}
