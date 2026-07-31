import ArgumentParser
import Foundation
import GRDB
import PrimeTimeCore

/// The scriptable surface (#80): `primetime start/stop/status` for scripts
/// and agent hooks (#79), `primetime export` for composable data access.
/// Data goes to stdout; logs, progress, and errors go to stderr.
@main
struct PrimeTimeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "primetime",
        abstract: "Scriptable access to the PrimeTime store: timer control and export.",
        subcommands: [Start.self, Stop.self, Status.self, Export.self])
}

// MARK: - Exit codes
//
// 0 success (for `status`: a timer is running) · 1 clean negative (`status`/
// `stop` with no running timer) · 2 anything went wrong. ArgumentParser's
// own usage errors keep their conventional 64.

/// Print to stderr — the channel for everything that isn't data.
func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Run a command body, mapping any thrown error to a stderr line and exit
/// code 2 — so 1 stays unambiguous as the "no running timer" result.
func mappingErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let exit as ExitCode {
        throw exit
    } catch {
        log("primetime: \(error.localizedDescription)")
        throw ExitCode(2)
    }
}

// MARK: - The store

/// Where the store lives and how to open it, shared by every subcommand.
struct StoreOptions: ParsableArguments {
    @Option(name: .customLong("db"),
            help: ArgumentHelp("Path to a primetime.sqlite store.",
                               discussion: "Defaults to the installed app's store, "
                                   + "then a dev build's; PRIMETIME_DB overrides."))
    var db: String?

    /// The store paths the app can be using: the bundled app resolves its
    /// Application Support directory from its bundle identifier, an
    /// unbundled dev build falls back to the target name (see
    /// `LocalBackend.defaultDatabaseURL`). The CLI has no bundle either, so
    /// it names the app's directory explicitly rather than inheriting the
    /// dev fallback.
    static func candidateURLs() throws -> [URL] {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        return ["tools.primetime.PrimeTime", "PrimeTime"].map {
            support.appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("primetime.sqlite")
        }
    }

    /// Resolve to an *existing* store. The CLI never creates one: a fresh
    /// empty database is never what `status` or `export` means, and silently
    /// making one would fork the data the app owns.
    func resolveURL() throws -> URL {
        let explicit = db ?? ProcessInfo.processInfo.environment["PRIMETIME_DB"]
        if let explicit {
            let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw LocalBackend.Error(message: "No store at \(url.path)")
            }
            return url
        }
        let candidates = try Self.candidateURLs()
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }
        throw LocalBackend.Error(message: """
            No PrimeTime store found. Looked for:
            \(candidates.map { "  " + $0.path }.joined(separator: "\n"))
            Is the app installed? (Or point at a store with --db / PRIMETIME_DB.)
            """)
    }

    /// Open the resolved store. A short busy timeout rides along because the
    /// app may hold the write lock for a moment; migrations are the same
    /// ones the app runs, so a store from the matching app version is a
    /// no-op to open.
    func open() throws -> LocalBackend {
        let url = try resolveURL()
        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        return try LocalBackend(DatabaseQueue(path: url.path, configuration: configuration),
                                databaseURL: url, legacyDefaults: nil)
    }
}

/// Tell a running app the store changed under it — fire-and-forget; nothing
/// listens when the app isn't running. Darwin-only: Linux Foundation has no
/// DistributedNotificationCenter, and there is no app to poke there anyway.
func notifyStoreChanged() {
    #if canImport(Darwin)
    DistributedNotificationCenter.default().postNotificationName(
        .primeTimeStoreDidChange, object: nil, userInfo: nil, deliverImmediately: true)
    #endif
}

// MARK: - Formatting

/// `key=value` pairs the way the `-l` flag spells them, for human output.
func describe(_ labels: [SpanLabel]) -> String {
    labels.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
}

/// A compact elapsed-time form: 47s, 12m, 3h07m.
func describeDuration(from start: Date, to end: Date) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(start)))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    return "\(minutes / 60)h" + String(format: "%02dm", minutes % 60)
}
