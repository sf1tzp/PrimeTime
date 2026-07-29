import Foundation
import Observation
import SwiftUI
import AppKit

/// The whole app's state and behaviour. `@MainActor` because everything here
/// drives the UI; `@Observable` so SwiftUI views re-render when it changes.
@MainActor
@Observable
final class AppModel {
    // MARK: Persisted configuration

    var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
            rebuildClient()
        }
    }

    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: Keys.deviceName) }
    }

    var tagSets: [TagSet] {
        didSet { saveTagSets() }
    }

    /// When on, tags are coloured by their `key: value` pair (using the local
    /// overrides below) instead of only by key, so `repo: foo` and `repo: bar`
    /// can look different.
    var colorTagsByValue: Bool {
        didSet { UserDefaults.standard.set(colorTagsByValue, forKey: Keys.colorTagsByValue) }
    }

    /// Per-`key: value` colour overrides (hex strings). Traggo only stores
    /// colours per key, so these are a client-side convenience like tag sets.
    var valueColors: [String: String] {
        didSet { UserDefaults.standard.set(valueColors, forKey: Keys.valueColors) }
    }

    /// How many tag sets the popover's Quick start list shows, in tag-set
    /// order; 0 means all. Keeps the popover a quick-glance surface when many
    /// sets are saved.
    var menuTagSetLimit: Int {
        didSet { UserDefaults.standard.set(menuTagSetLimit, forKey: Keys.menuTagSetLimit) }
    }

    // MARK: Runtime state (observed by the UI)

    var user: User?
    /// Every running timespan, oldest first — the first-started timer stays at
    /// the top of the popover and new ones join below. Traggo allows
    /// overlapping timespans, and the menu can start one alongside another
    /// (the ＋ on a quick-start row, the blank-timer row), so this is a list
    /// rather than a single timer.
    var activeTimers: [TimeSpan] = []
    var tagDefinitions: [TagDefinition] = []

    /// The first-started running timespan — the popover's top row and the one
    /// the menu-bar label counts up for.
    var activeTimer: TimeSpan? { activeTimers.first }
    var errorMessage: String?
    var isBusy = false
    /// Updated once per second while a timer runs so elapsed labels tick.
    var currentDate = Date()

    var isAuthenticated: Bool { user != nil }

    /// History (log / calendar / charts) state, split out so this class stays
    /// focused on live-timer concerns.
    @ObservationIgnored private(set) lazy var history = HistoryModel(app: self)

    // MARK: Private, non-observed

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var client: TraggoClient?

    /// The current client, for sibling models (see `HistoryModel`). Rebuilt when
    /// the server URL or token changes, hence exposed as a computed property.
    var api: TraggoClient? { client }
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTimer: Timer?
    /// Debounce timers for per-key colour writes, so dragging in the colour
    /// picker doesn't fire an `updateTag` on every intermediate value.
    @ObservationIgnored private var colorTasks: [String: Task<Void, Never>] = [:]

    private enum Keys {
        static let serverURL = "serverURL"
        static let deviceName = "deviceName"
        // Stored under the legacy "presets" key so existing saved sets survive.
        static let tagSets = "presets"
        static let colorTagsByValue = "colorTagsByValue"
        static let valueColors = "valueColors"
        static let menuTagSetLimit = "menuTagSetLimit"
    }

    // MARK: Lifecycle

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: Keys.serverURL) ?? "https://traggo.lofi"
        deviceName = defaults.string(forKey: Keys.deviceName)
            ?? "Menu Bar (\(Host.current().localizedName ?? "Mac"))"
        tagSets = AppModel.loadTagSets()
        colorTagsByValue = defaults.bool(forKey: Keys.colorTagsByValue)
        valueColors = defaults.dictionary(forKey: Keys.valueColors) as? [String: String] ?? [:]
        menuTagSetLimit = defaults.object(forKey: Keys.menuTagSetLimit) == nil
            ? 5 : defaults.integer(forKey: Keys.menuTagSetLimit)  // 0 = all
        token = Keychain.get(account: "token")

        rebuildClient()
        startTicking()
        Task { await bootstrap() }
    }

    private func rebuildClient() {
        guard let url = URL(string: serverURL) else {
            client = nil
            return
        }
        client = TraggoClient(baseURL: url, token: token)
    }

    private func bootstrap() async {
        guard token != nil else { return }
        await validateSession()
    }

    // MARK: Auth

    private func validateSession() async {
        guard let client else { return }
        do {
            if let user = try await client.currentUser() {
                self.user = user
                startPolling()
                await refresh()
            } else {
                logout() // token no longer valid
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func login(username: String, password: String) async {
        guard let client else {
            errorMessage = "Invalid server URL"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await client.login(username: username,
                                                password: password,
                                                deviceName: deviceName)
            token = result.token
            Keychain.set(result.token, account: "token")
            rebuildClient()          // client now carries the token
            user = result.user
            errorMessage = nil
            startPolling()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        pollTask?.cancel()
        token = nil
        Keychain.delete(account: "token")
        user = nil
        activeTimers = []
        tagDefinitions = []
        rebuildClient()
    }

    // MARK: Data

    func refresh() async {
        guard let client, isAuthenticated else { return }
        do {
            async let timers = client.timers()
            async let tags = client.tags()
            let (runningTimers, definitions) = try await (timers, tags)
            activeTimers = runningTimers.sorted { $0.start.date < $1.start.date }
            tagDefinitions = definitions
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(tagSet: TagSet) async {
        await start(tags: tagSet.wireTags)
    }

    /// Start a timespan with the given tags — empty for an ad-hoc timer that
    /// gets classified while it runs. Returns the created timespan so the
    /// caller can e.g. open it for editing right away.
    @discardableResult
    func start(tags: [TimeSpanTag]) async -> TimeSpan? {
        guard let client else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureTagDefinitions(for: tags)
            // No note at start; the note is added on the running timer.
            let created = try await client.startTimeSpan(start: Date(),
                                                         tags: tags,
                                                         note: "")
            activeTimers.append(created)   // newest last, until refresh re-sorts
            errorMessage = nil
            await refresh()
            await history.reloadIfLoaded()
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Ensure every tag key exists as a definition, or the server rejects the
    /// timespan. Creates missing ones with a default colour.
    func ensureTagDefinitions(for tags: [TimeSpanTag]) async throws {
        guard let client else { return }
        let existing = Set(tagDefinitions.map(\.key))
        for tag in tags where !existing.contains(tag.key) {
            try await client.createTag(key: tag.key, color: "#2196f3")
        }
    }

    /// Update the tags and note on a running timespan, preserving its start.
    /// Missing tag definitions are created first (traggo rejects unknown
    /// keys), the same guard `start(tags:)` uses.
    func updateRunning(id: Int, tags: [TimeSpanTag], note: String) async {
        guard let client,
              let span = activeTimers.first(where: { $0.id == id }) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureTagDefinitions(for: tags)
            let updated = try await client.updateTimeSpan(
                id: span.id, start: span.start.date, end: span.end?.date,
                tags: tags, note: note)
            replaceActiveTimer(with: updated)
            errorMessage = nil
            await history.reloadIfLoaded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stop a running timespan — a specific one, or the top row's by default.
    func stop(id: Int? = nil) async {
        guard let client, let target = id ?? activeTimer?.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.stopTimeSpan(id: target, end: Date())
            activeTimers.removeAll { $0.id == target }
            errorMessage = nil
            await refresh()
            await history.reloadIfLoaded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaceActiveTimer(with updated: TimeSpan) {
        if let index = activeTimers.firstIndex(where: { $0.id == updated.id }) {
            activeTimers[index] = updated
        }
    }

    /// Whether some running timespan carries exactly this set's tags — used to
    /// hide a quick-start set while "it" runs. Matching by tags (not by which
    /// row was clicked) also catches a matching timespan started from the web
    /// UI, and the set reappears naturally when the timespan stops.
    func isRunning(_ set: TagSet) -> Bool {
        let want = Set(set.wireTags)
        return activeTimers.contains { Set($0.tags ?? []) == want }
    }

    // MARK: Tag colours (stored server-side, per key)

    /// The colour to render a tag with. With "colour by value" on, a local
    /// per-value override wins; otherwise the colour Traggo has on record for
    /// the tag key, or a sensible default.
    func tagColor(for rawKey: String, value: String? = nil) -> Color {
        if colorTagsByValue, let value,
           let color = valueColor(key: rawKey, value: value) {
            return color
        }
        let key = normalizeKey(rawKey)
        if let hex = tagDefinitions.first(where: { $0.key == key })?.color,
           let color = Color(hex: hex) {
            return color
        }
        return Color(hex: "#2196f3") ?? .blue
    }

    // MARK: Per-value colour overrides (stored locally)

    /// Composite dictionary key — a unit separator rather than ":" because tag
    /// values may themselves contain ":".
    private static func valueColorKey(_ key: String, _ value: String) -> String {
        "\(key)\u{1F}\(value)"
    }

    /// The override picked for a `key: value` pair, if any.
    func valueColor(key rawKey: String, value: String) -> Color? {
        guard !value.isEmpty else { return nil }
        return valueColors[Self.valueColorKey(normalizeKey(rawKey), value)]
            .flatMap { Color(hex: $0) }
    }

    func setValueColor(key rawKey: String, value: String, color: Color) {
        guard let hex = color.hexString, !value.isEmpty else { return }
        valueColors[Self.valueColorKey(normalizeKey(rawKey), value)] = hex
    }

    func clearValueColor(key rawKey: String, value: String) {
        valueColors.removeValue(forKey: Self.valueColorKey(normalizeKey(rawKey), value))
    }

    /// Persist a new colour for a tag key, debounced so a colour-wheel drag
    /// collapses into a single write once it settles.
    func scheduleTagColor(for rawKey: String, color: Color) {
        let key = normalizeKey(rawKey)
        guard !key.isEmpty else { return }
        colorTasks[key]?.cancel()
        colorTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await self?.commitTagColor(key: key, color: color)
        }
    }

    private func commitTagColor(key: String, color: Color) async {
        guard let client, let hex = color.hexString else { return }
        do {
            // updateTag needs an existing key; createTag reserves a new one.
            if tagDefinitions.contains(where: { $0.key == key }) {
                try await client.updateTag(key: key, color: hex)
            } else {
                try await client.createTag(key: key, color: hex)
            }
            await refresh()   // pull the updated definitions back
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Menu-bar label + elapsed formatting

    var menuBarLabel: String? {
        guard let active = activeTimer else { return nil }
        return "● " + elapsedString(since: active.start.date)
    }

    func elapsedString(since start: Date) -> String {
        let seconds = max(0, Int(currentDate.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    // MARK: Polling + ticking

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func startTicking() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor to touch state.
            Task { @MainActor in
                guard let self, self.activeTimer != nil else { return }
                self.currentDate = Date()
            }
        }
    }

    // MARK: Tag-set persistence

    private static func loadTagSets() -> [TagSet] {
        guard let data = UserDefaults.standard.data(forKey: Keys.tagSets),
              let sets = try? JSONDecoder().decode([TagSet].self, from: data) else {
            return TagSet.samples
        }
        return sets
    }

    private func saveTagSets() {
        if let data = try? JSONEncoder().encode(tagSets) {
            UserDefaults.standard.set(data, forKey: Keys.tagSets)
        }
    }
}
