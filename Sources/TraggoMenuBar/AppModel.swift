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

    // MARK: Runtime state (observed by the UI)

    var user: User?
    var activeTimer: TimeSpan?
    var tagDefinitions: [TagDefinition] = []
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
    }

    // MARK: Lifecycle

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: Keys.serverURL) ?? "https://traggo.lofi"
        deviceName = defaults.string(forKey: Keys.deviceName)
            ?? "Menu Bar (\(Host.current().localizedName ?? "Mac"))"
        tagSets = AppModel.loadTagSets()
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
        activeTimer = nil
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
            activeTimer = runningTimers.first  // newest running timespan
            tagDefinitions = definitions
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(tagSet: TagSet) async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let wireTags = tagSet.wireTags
            try await ensureTagDefinitions(for: wireTags)
            // Tag sets carry no note; the note is added on the running timer.
            let created = try await client.startTimeSpan(start: Date(),
                                                         tags: wireTags,
                                                         note: "")
            activeTimer = created
            errorMessage = nil
            await refresh()
            await history.reloadIfLoaded()
        } catch {
            errorMessage = error.localizedDescription
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

    /// Update the note on the running timespan, preserving its start and tags.
    func updateNote(_ note: String) async {
        guard let client, let active = activeTimer else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let updated = try await client.updateTimeSpan(
                id: active.id, start: active.start.date, end: active.end?.date,
                tags: active.tags ?? [], note: note)
            activeTimer = updated
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard let client, let active = activeTimer else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.stopTimeSpan(id: active.id, end: Date())
            activeTimer = nil
            errorMessage = nil
            await refresh()
            await history.reloadIfLoaded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Tag colours (stored server-side, per key)

    /// The colour Traggo has on record for a tag key, or a sensible default.
    func tagColor(for rawKey: String) -> Color {
        let key = normalizeKey(rawKey)
        if let hex = tagDefinitions.first(where: { $0.key == key })?.color,
           let color = Color(hex: hex) {
            return color
        }
        return Color(hex: "#2196f3") ?? .blue
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
