import Foundation
import PrimeTimeCore
import Observation
import SwiftUI
import AppKit

/// The whole app's state and behaviour. `@MainActor` because everything here
/// drives the UI; `@Observable` so SwiftUI views re-render when it changes.
///
/// Storage model (#33): the local SQLite store is the *only* backend — every
/// read and write goes through it, no server required. Connecting a sync
/// server doesn't switch backends; it attaches a `SyncEngine` that
/// reconciles the same store with the server in the background, which is
/// what turns tag sets, colours, and preferences from per-Mac into per-user.
/// The old live-traggo mode is gone; `TraggoClient` survives only as the
/// importer's source.
@MainActor
@Observable
final class AppModel {
    /// True when launched in demo mode (#39). The whole session is then
    /// sandboxed: the local store is a regenerated `demo.sqlite`, `defaults`
    /// is a wiped scratch suite, the keychain token is ignored, and Settings
    /// hides the storage picker — so nothing done in a demo can touch real
    /// data or preferences.
    let isDemo: Bool

    /// Where every settings read/write goes: the standard domain normally, a
    /// scratch suite in demo mode. One indirection instead of guards at each
    /// call site.
    @ObservationIgnored private let defaults: UserDefaults

    /// Sparkle auto-update (#46). Inert (nil controller) in dev builds, tests
    /// and demo mode — see UpdaterModel.
    let updater: UpdaterModel

    // MARK: Persisted configuration

    /// The traggo server URL — import-only now: the one-shot importer's
    /// source. (The sync server's URL lives in the store's sync_server row.)
    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    var deviceName: String {
        didSet { defaults.set(deviceName, forKey: Keys.deviceName) }
    }

    /// The saved tag sets, persisted in the local store.
    var tagSets: [TagSet] {
        didSet { persistTagSets() }
    }

    /// Quick labels per label set, keyed by the set's UUID string — one-click
    /// refinements the popover and Launcher offer on hover (#61): a set covers
    /// the focus area (`repo:`, `feat:`) and a quick label hones in
    /// (`type: review`). Per-set rather than global so e.g. a Workout set
    /// isn't offered `type: programming`; the copy/paste clipboard below
    /// spreads one list across sets without retyping. Stored as JSON in
    /// UserDefaults, per-Mac until server sync exists (#92). Entries for
    /// deleted sets linger harmlessly.
    var quickLabels: [String: [TagRow]] {
        didSet { persistQuickLabels() }
    }

    /// The copy/paste clipboard for quick labels in the Label Set editor.
    /// Session-only by design: it's a hand-off between two edits, not state
    /// worth keeping.
    var quickLabelsClipboard: [TagRow]?

    /// The quick labels to offer for a set (empty when none are defined).
    func quickLabels(for set: TagSet) -> [TagRow] {
        quickLabels[set.id.uuidString] ?? []
    }

    /// When on, tags are coloured by their `key: value` pair (using the local
    /// overrides below) instead of only by key, so `repo: foo` and `repo: bar`
    /// can look different. On by default — differentiating spans by value is
    /// PrimeTime's headline improvement over vanilla traggo, with key colours
    /// remaining useful for navigating Tag Review; an explicitly stored false
    /// (a user who turned it off) is respected. Syncs as a user preference
    /// when a server is connected.
    var colorTagsByValue: Bool {
        didSet {
            defaults.set(colorTagsByValue, forKey: Keys.colorTagsByValue)
            preferenceChanged()
        }
    }

    /// Per-`key: value` colour overrides (hex strings), keyed by
    /// `ValueColorKey.join` — first-class rows in the local store, and
    /// per-user (not per-Mac) once a sync server is connected.
    var valueColors: [String: String] {
        didSet { persistValueColors() }
    }

    /// How many tag sets the popover's Quick start list shows, in tag-set
    /// order; 0 means all. Keeps the popover a quick-glance surface when many
    /// sets are saved. Syncs as a user preference when a server is connected.
    var menuTagSetLimit: Int {
        didSet {
            defaults.set(menuTagSetLimit, forKey: Keys.menuTagSetLimit)
            preferenceChanged()
        }
    }

    // MARK: Runtime state (observed by the UI)

    var user: User?
    /// Every running timespan, oldest first — the first-started timer stays at
    /// the top of the popover and new ones join below. Traggo allows
    /// overlapping timespans, and the menu can start one alongside another
    /// (the ＋ on a quick-start row, the blank-timer row), so this is a list
    /// rather than a single timer.
    var activeTimers: [TimeSpan] = []
    var tagDefinitions: [LabelDefinition] = []

    /// The first-started running timespan — the popover's top row and the one
    /// the menu-bar label counts up for.
    var activeTimer: TimeSpan? { activeTimers.first }
    var errorMessage: String?
    var isBusy = false
    /// Updated once per second while a timer runs so elapsed labels tick.
    var currentDate = Date()

    /// Whether the store is ready to serve data — as soon as it opens (its
    /// `user` is set synchronously); false only if opening the database
    /// failed.
    var isReady: Bool { user != nil }

    /// History (log / calendar / charts) state, split out so this class stays
    /// focused on live-timer concerns.
    @ObservationIgnored private(set) lazy var history = HistoryModel(app: self)

    /// Tag review (cardinality + cleanup) state, split out for the same reason.
    @ObservationIgnored private(set) lazy var review = TagReviewModel(app: self)

    // MARK: Private, non-observed

    /// The saved traggo session token — import-only: it lets a re-import skip
    /// the credential prompt. Not observation-ignored: the import surface's
    /// `hasTraggoSession` reads it, and must react when a one-off login saves
    /// one or an expired one is dropped.
    private var token: String?
    /// The local store — the only backend. Opened at launch and kept open for
    /// the app's lifetime.
    @ObservationIgnored private var localStore: LocalBackend?
    /// Suppresses the tagSets/valueColors/preference persistence observers
    /// while they're being *loaded* (from the store or from a sync pull), so
    /// restoring state never echoes a write or re-dirties a synced record.
    @ObservationIgnored private var isRestoringState = false

    /// The storage seam, for this model and its siblings (see
    /// `HistoryModel`). Always the local store; the protocol survives
    /// because the importer still consumes arbitrary backends.
    var api: (any Backend)? { localStore }

    /// Where the local database lives, for display in Settings.
    var localDatabasePath: String? {
        localStore?.databaseURL?.path
    }
    @ObservationIgnored private var tickTimer: Timer?
    /// Registration for the CLI's cross-process store-changed notification.
    @ObservationIgnored private var storeChangeObserver: NSObjectProtocol?
    /// Debounce timers for per-key colour writes, so dragging in the colour
    /// picker doesn't fire an `updateTag` on every intermediate value.
    @ObservationIgnored private var colorTasks: [String: Task<Void, Never>] = [:]

    private enum Keys {
        static let serverURL = "serverURL"
        static let deviceName = "deviceName"
        // Stored under the legacy "presets" key so existing saved sets survive.
        static let tagSets = "presets"
        static let quickLabels = "quickLabelsBySet"
        static let colorTagsByValue = "colorTagsByValue"
        static let valueColors = "valueColors"
        static let menuTagSetLimit = "menuTagSetLimit"
        /// Keychain accounts: the sync server's device token, and the legacy
        /// traggo token the importer still reuses.
        static let syncToken = "sync-token"
        static let traggoToken = "token"
    }

    // MARK: Lifecycle

    init(demo: Bool = DemoMode.isActive) {
        isDemo = demo
        updater = UpdaterModel(demo: demo)
        let defaults = Self.makeDefaults(demo: demo)
        self.defaults = defaults
        serverURL = defaults.string(forKey: Keys.serverURL) ?? "https://traggo.lofi"
        deviceName = defaults.string(forKey: Keys.deviceName)
            ?? "Menu Bar (\(Host.current().localizedName ?? "Mac"))"
        colorTagsByValue = defaults.object(forKey: Keys.colorTagsByValue) == nil
            ? true : defaults.bool(forKey: Keys.colorTagsByValue)  // default on
        menuTagSetLimit = defaults.object(forKey: Keys.menuTagSetLimit) == nil
            ? 5 : defaults.integer(forKey: Keys.menuTagSetLimit)  // 0 = all
        // Into a local first: `token` is observation-tracked, and a tracked
        // property can't be *read* before the whole object is initialised.
        // A demo never reads the real token — nothing in a demo may reach a
        // real server.
        token = demo ? nil : Keychain.get(account: Keys.traggoToken)
        tagSets = []          // loaded by activateStore()
        valueColors = [:]
        if let data = defaults.data(forKey: Keys.quickLabels),
           let rows = try? JSONDecoder().decode([String: [TagRow]].self, from: data) {
            quickLabels = rows
        } else {
            quickLabels = [:]   // demo seeding needs set ids — activateStore()
        }

        activateStore()
        startSyncIfConfigured()
        startTicking()
        startObservingStoreChanges()
        Task { await refresh() }
    }

    /// Demo sessions read and write a scratch suite, wiped on each launch, so
    /// they start from stock settings and a toggle flipped for a screenshot
    /// never lands in the real preferences.
    private static func makeDefaults(demo: Bool) -> UserDefaults {
        guard demo else { return .standard }
        let suite = "PrimeTimeDemo"
        let defaults = UserDefaults(suiteName: suite)!   // constant, valid name
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Open the store (running its migrations, including the one-time
    /// UserDefaults import) and load the state it owns.
    private func activateStore() {
        isRestoringState = true
        defer { isRestoringState = false }
        do {
            // Demo mode rebuilds and reseeds demo.sqlite instead —
            // the real database is never even opened.
            localStore = isDemo ? try LocalBackend.demo() : try LocalBackend()
        } catch {
            errorMessage = "Could not open the local database: \(error.localizedDescription)"
        }
        if let store = localStore {
            tagSets = (try? store.loadTagSets()) ?? []
            valueColors = (try? store.loadValueColors()) ?? [:]
            user = LocalBackend.localUser   // no login; ready immediately
            // Demo quick labels are keyed by the set ids minted during this
            // launch's reseed, so they can only be attached here, after the
            // sets load. The scratch defaults suite is wiped each launch, so
            // the check against existing entries never blocks the seed.
            if isDemo && quickLabels.isEmpty {
                for set in tagSets {
                    if let rows = DemoSeed.quickLabels(forSetNamed: set.name) {
                        quickLabels[set.id.uuidString] = rows
                    }
                }
            }
        }
    }

    // MARK: Sync server (#33)

    /// The engine reconciling the store with a connected sync server; nil
    /// when no server is connected (or in demo mode — a demo never syncs).
    var syncEngine: SyncEngine?
    /// The connection row, mirrored from the store for Settings to display.
    var syncServer: SyncServerRow?
    var isConnectingSync = false
    var syncConnectError: String?

    /// Re-attach the engine for a connection that survives a relaunch: an
    /// active sync_server row in the store plus the device token in the
    /// Keychain.
    private func startSyncIfConfigured() {
        guard !isDemo, let store = localStore else { return }
        syncServer = try? store.syncServer()
        guard let row = syncServer, row.active,
              let token = Keychain.get(account: Keys.syncToken),
              let url = URL(string: row.url) else { return }
        startSyncEngine(client: PrimeTimeClient(baseURL: url, token: token))
        syncEngine?.kick(after: 1)
    }

    /// Mint a device token on the sync server, remember the connection, and
    /// run the first reconciliation. The password is used once and never
    /// stored; the token goes to the Keychain.
    func connectSyncServer(url: String, username: String, password: String) async {
        guard !isDemo, let store = localStore, !isConnectingSync else { return }
        var normalized = url.trimmingCharacters(in: .whitespaces)
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let serverURL = URL(string: normalized), serverURL.scheme != nil else {
            syncConnectError = "Invalid server URL"
            return
        }
        isConnectingSync = true
        defer { isConnectingSync = false }
        do {
            var client = PrimeTimeClient(baseURL: serverURL, token: nil)
            let result = try await client.login(username: username,
                                                password: password,
                                                deviceName: deviceName)
            Keychain.set(result.token, account: Keys.syncToken)
            try store.connectSyncServer(url: normalized, user: result.user)
            syncServer = try? store.syncServer()
            client.token = result.token
            syncConnectError = nil
            startSyncEngine(client: client)
            await syncEngine?.syncNow()
        } catch {
            syncConnectError = error.localizedDescription
        }
    }

    /// Stop syncing. Local data, server-id mappings, and clean/dirty state
    /// all stay, so reconnecting to the same server resumes instead of
    /// duplicating.
    func disconnectSyncServer() {
        syncEngine?.stop()
        syncEngine = nil
        try? localStore?.disconnectSyncServer()
        Keychain.delete(account: Keys.syncToken)
        syncServer = try? localStore?.syncServer()
    }

    private func startSyncEngine(client: PrimeTimeClient) {
        guard let store = localStore else { return }
        let engine = SyncEngine(store: store, server: client)
        engine.readPreferences = { [weak self] in
            (self?.colorTagsByValue ?? true, self?.menuTagSetLimit ?? 5)
        }
        engine.applyPreferences = { [weak self] colorByValue, limit in
            guard let self else { return }
            self.isRestoringState = true
            defer { self.isRestoringState = false }
            self.colorTagsByValue = colorByValue
            self.menuTagSetLimit = limit
        }
        engine.onLocalChange = { [weak self] in
            guard let self else { return }
            self.reloadFromStore()
            Task {
                await self.refresh()
                await self.history.reloadIfLoaded()
            }
        }
        engine.startPeriodicSync()
        syncEngine = engine
    }

    /// A local mutation happened — reconcile soon. Called by every write
    /// path here and in the sibling models; harmlessly does nothing when no
    /// server is connected.
    func syncSoon() {
        syncEngine?.kick()
    }

    /// One of the two synced preferences changed by hand: stamp it dirty in
    /// the store (a no-op until a server is connected) and reconcile soon.
    private func preferenceChanged() {
        guard !isRestoringState else { return }
        try? localStore?.markPreferencesDirty()
        syncSoon()
    }

    /// Re-read the state a sync pull may have rewritten (tag sets, value
    /// colours) without echoing the loads back as writes.
    private func reloadFromStore() {
        guard let store = localStore else { return }
        isRestoringState = true
        defer { isRestoringState = false }
        tagSets = (try? store.loadTagSets()) ?? []
        valueColors = (try? store.loadValueColors()) ?? [:]
    }

    // MARK: Import from traggo (#30)

    /// Live state of the one-shot traggo import, observed by the Settings
    /// pane. Errors are kept apart from `errorMessage` so a background
    /// refresh can't overwrite a failed import's explanation.
    var isImporting = false
    /// Spans upserted so far, for progress while the import walks pages.
    var importedSpanCount = 0
    var importSummary: ImportSummary?
    var importError: String?

    /// Whether a traggo session is saved (in the Keychain) — the import can
    /// reuse it instead of asking for credentials.
    var hasTraggoSession: Bool { token != nil }

    /// One-shot import of a traggo server's full history into the local
    /// store — `TraggoClient`'s only remaining job. Pass credentials only
    /// when no saved session exists (or the saved one expired): a successful
    /// one-off login keeps its token so re-runs are already signed in.
    func importFromTraggo(username: String = "", password: String = "") async {
        guard !isImporting else { return }
        guard let store = localStore else {
            importError = "The local database isn't open."
            return
        }
        guard let url = URL(string: serverURL) else {
            importError = "Invalid server URL"
            return
        }
        var client = TraggoClient(baseURL: url, token: token)
        isImporting = true
        importedSpanCount = 0
        importSummary = nil
        importError = nil
        defer { isImporting = false }
        do {
            if !username.isEmpty {
                let result = try await client.login(username: username,
                                                    password: password,
                                                    deviceName: deviceName)
                token = result.token
                Keychain.set(result.token, account: Keys.traggoToken)
                client.token = result.token
            } else if try await client.currentUser() == nil {
                // The saved token is dead. Drop it — hasTraggoSession flips,
                // so the credential fields appear next to this explanation.
                token = nil
                Keychain.delete(account: Keys.traggoToken)
                importError = "The saved sign-in has expired — enter your username and password."
                return
            }
            // The origin string namespaces the server's span ids in the local
            // mapping. Use the parsed URL (trailing slash trimmed) so trivial
            // respellings of the same server don't fork the namespace.
            var origin = client.baseURL.absoluteString
            while origin.hasSuffix("/") { origin.removeLast() }
            let importer = HistoryImporter(source: client, destination: store,
                                           origin: origin)
            let summary = try await importer.run { count in
                await MainActor.run { self.importedSpanCount = count }
            }
            importSummary = summary
            // Imported data is live state: running traggo timers now tick in
            // the popover, and key colours reach every tag chip — and it has
            // to reach a connected sync server like any other local write.
            await refresh()
            await history.reloadIfLoaded()
            syncSoon()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: Export (#57)

    /// The store's JSON snapshot, for the Settings export button. Works in
    /// demo mode too — it just snapshots the demo store.
    func exportJSON() throws -> Data {
        guard let store = localStore else {
            throw LocalBackend.Error(message: "The local database isn't open.")
        }
        return try store.exportJSON()
    }

    // MARK: Data

    func refresh() async {
        guard let backend = api, isReady else { return }
        do {
            async let timers = backend.timers()
            async let definitions = backend.labelDefinitions()
            let (runningTimers, labelDefinitions) = try await (timers, definitions)
            activeTimers = runningTimers.sorted { $0.start < $1.start }
            tagDefinitions = labelDefinitions
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(tagSet: TagSet) async {
        await start(tags: tagSet.labels)
    }

    /// Start a timespan with the given tags — empty for an ad-hoc timer that
    /// gets classified while it runs. Returns the created timespan so the
    /// caller can e.g. open it for editing right away.
    @discardableResult
    func start(tags: [SpanLabel]) async -> TimeSpan? {
        guard let backend = api else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureTagDefinitions(for: tags)
            // No note at start; the note is added on the running timer.
            let created = try await backend.startTimeSpan(start: Date(),
                                                          labels: tags,
                                                          note: "")
            activeTimers.append(created)   // newest last, until refresh re-sorts
            errorMessage = nil
            await refresh()
            await history.reloadIfLoaded()
            syncSoon()
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Ensure every tag key exists as a definition, or the server rejects the
    /// timespan. Creates missing ones with a default colour.
    func ensureTagDefinitions(for tags: [SpanLabel]) async throws {
        guard let backend = api else { return }
        let existing = Set(tagDefinitions.map(\.key))
        for tag in tags where !existing.contains(tag.key) {
            try await backend.createLabelDefinition(key: tag.key, color: "#2196f3")
        }
    }

    /// Update the tags and note on a running timespan, preserving its start.
    /// Missing tag definitions are created first (traggo rejects unknown
    /// keys), the same guard `start(tags:)` uses.
    func updateRunning(id: Int, tags: [SpanLabel], note: String) async {
        guard let backend = api,
              let span = activeTimers.first(where: { $0.id == id }) else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureTagDefinitions(for: tags)
            let updated = try await backend.updateTimeSpan(
                id: span.id, start: span.start, end: span.end,
                labels: tags, note: note)
            replaceActiveTimer(with: updated)
            errorMessage = nil
            await history.reloadIfLoaded()
            syncSoon()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stop a running timespan — a specific one, or the top row's by default.
    func stop(id: Int? = nil) async {
        guard let backend = api, let target = id ?? activeTimer?.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await backend.stopTimeSpan(id: target, end: Date())
            activeTimers.removeAll { $0.id == target }
            errorMessage = nil
            await refresh()
            await history.reloadIfLoaded()
            syncSoon()
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
        runningTimer(for: set) != nil
    }

    /// The running timespan carrying exactly this set's tags, if any — same
    /// tag-equality rule as `isRunning(_:)`. Lets a surface that shows sets
    /// (the Launcher) stop "the set's" timer by id.
    func runningTimer(for set: TagSet) -> TimeSpan? {
        let want = Set(set.labels)
        return activeTimers.first { Set($0.labels) == want }
    }

    // MARK: Creating tag sets from existing tags

    /// Whether some saved tag set carries exactly these tags — exact set
    /// equality, same rule as `isRunning(_:)`. Log rows without a match offer
    /// "save these tags as a tag set".
    func hasTagSet(matching tags: [SpanLabel]) -> Bool {
        let want = Set(tags)
        return tagSets.contains { Set($0.labels) == want }
    }

    /// Set when another surface (a Log row's ＋, the Launcher's ＋ card)
    /// creates a tag set and wants the Tag Sets pane to open on it.
    /// Consumed by the pane when it appears or sees the change.
    var pendingTagSetSelection: TagSet.ID?

    /// Append a fresh tag set — seeded from existing tags when given — and
    /// mark it for selection in the Tag Sets pane, where the user names it.
    @discardableResult
    func newTagSet(from tags: [SpanLabel] = []) -> TagSet {
        let set = TagSet(name: "New tag set",
                         tags: tags.map { TagRow(key: $0.key, value: $0.value) })
        tagSets.append(set)
        pendingTagSetSelection = set.id
        return set
    }

    // MARK: Tag colours (stored per key by the backend)

    /// The colour to render a tag with. With "colour by value" on, a
    /// per-value override wins; otherwise the colour the backend has on
    /// record for the tag key, or a sensible default.
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

    // MARK: Per-value colour overrides

    /// The override picked for a `key: value` pair, if any.
    func valueColor(key rawKey: String, value: String) -> Color? {
        guard !value.isEmpty else { return nil }
        return valueColors[ValueColorKey.join(normalizeKey(rawKey), value)]
            .flatMap { Color(hex: $0) }
    }

    func setValueColor(key rawKey: String, value: String, color: Color) {
        guard let hex = color.hexString, !value.isEmpty else { return }
        valueColors[ValueColorKey.join(normalizeKey(rawKey), value)] = hex
    }

    func clearValueColor(key rawKey: String, value: String) {
        valueColors.removeValue(forKey: ValueColorKey.join(normalizeKey(rawKey), value))
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
        guard let backend = api, let hex = color.hexString else { return }
        do {
            // update needs an existing key; create reserves a new one.
            if tagDefinitions.contains(where: { $0.key == key }) {
                try await backend.updateLabelDefinition(key: key, color: hex)
            } else {
                try await backend.createLabelDefinition(key: key, color: hex)
            }
            await refresh()   // pull the updated definitions back
            syncSoon()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Menu-bar label + elapsed formatting

    var menuBarLabel: String? {
        guard let active = activeTimer else { return nil }
        return "● " + elapsedString(since: active.start)
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

    // MARK: Ticking

    private func startTicking() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor to touch state.
            Task { @MainActor in
                guard let self, self.activeTimer != nil else { return }
                self.currentDate = Date()
            }
        }
    }

    /// The primetime CLI (#80) writes the store from another process and
    /// posts a distributed notification (see StoreChangeNotification.swift in
    /// PrimeTimeCore) — there is no cross-process store observation, so this
    /// is how those writes reach a running app. Re-read the live surfaces and
    /// give sync a kick: a CLI-started span is dirty local data like any
    /// other. Not in demo mode — a demo session runs on its own throwaway
    /// store, not the one the CLI targets.
    private func startObservingStoreChanges() {
        guard !isDemo else { return }
        storeChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: .primeTimeStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refresh()
                await self.history.reloadIfLoaded()
                self.syncSoon()
            }
        }
    }

    // MARK: Tag-set + value-colour persistence

    private func persistTagSets() {
        guard !isRestoringState else { return }
        do { try localStore?.saveTagSets(tagSets) }
        catch { errorMessage = error.localizedDescription }
        syncSoon()
    }

    private func persistValueColors() {
        guard !isRestoringState else { return }
        do { try localStore?.saveValueColors(valueColors) }
        catch { errorMessage = error.localizedDescription }
        syncSoon()
    }

    private func persistQuickLabels() {
        if let data = try? JSONEncoder().encode(quickLabels) {
            defaults.set(data, forKey: Keys.quickLabels)
        }
    }
}
