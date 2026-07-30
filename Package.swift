// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PrimeTime",
    platforms: [
        // macOS 14 gives us MenuBarExtra + the Observation framework (@Observable).
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PrimeTime", targets: ["PrimeTime"]),
        // The scriptable CLI (#80). The product is `primetime-cli`, not
        // `primetime`: on a case-insensitive filesystem that binary would
        // collide with the app's inside .build/. Distribution installs it
        // under the plain name (see bundle-app.sh).
        .executable(name: "primetime-cli", targets: ["PrimeTimeCLI"])
    ],
    dependencies: [
        // The local store (LocalBackend.swift): SQLite chosen over SwiftData
        // because GRDB records are plain Codable structs, so the existing
        // domain values persist without a mapping layer (see issue #23).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // In-app auto-update (issue #46). The SPM distribution is a prebuilt
        // XCFramework; bundle-app.sh copies it into Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        // Command parsing for the CLI target only.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        // The store and its domain (#80): everything the app and the CLI
        // share — domain types, the GRDB store, the export document, sync
        // bookkeeping, demo seeding. The cross-module surface uses `package`
        // access, so extracting the library makes nothing public API.
        .target(
            name: "PrimeTimeCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/PrimeTimeCore"
        ),
        .executableTarget(
            name: "PrimeTime",
            dependencies: [
                "PrimeTimeCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PrimeTime",
            linkerSettings: [
                // Sparkle.framework rides in the .app at Contents/Frameworks;
                // SwiftPM only adds an rpath into .build/artifacts (which also
                // keeps unbundled dev builds working), so add the bundle-
                // relative one ourselves.
                .unsafeFlags(["-Xlinker", "-rpath",
                              "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // The scriptable surface (#80): export to stdout, timer start/stop/
        // status for scripts and agent hooks (#79). Talks to the same store
        // file the app uses, through the same PrimeTimeCore code.
        .executableTarget(
            name: "PrimeTimeCLI",
            dependencies: [
                "PrimeTimeCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/PrimeTimeCLI"
        ),
        .testTarget(
            name: "PrimeTimeTests",
            // GRDB so tests can hand LocalBackend an in-memory DatabaseQueue
            // and inspect rows directly.
            dependencies: ["PrimeTime", "PrimeTimeCore",
                           .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/PrimeTimeTests"
        )
    ],
    // Tools 6.0 only for the Swift Testing integration; the code stays in the
    // Swift 5 language mode rather than adopting strict concurrency as a side
    // effect. With full Xcode, `swift test` just works; on a Command Line
    // Tools-only machine, point it at the CLT copy of Testing.framework:
    //   CLT=/Library/Developer/CommandLineTools
    //   swift test -Xswiftc -F -Xswiftc $CLT/Library/Developer/Frameworks \
    //     -Xlinker -F -Xlinker $CLT/Library/Developer/Frameworks \
    //     -Xlinker -rpath -Xlinker $CLT/Library/Developer/Frameworks \
    //     -Xlinker -rpath -Xlinker $CLT/Library/Developer/usr/lib
    swiftLanguageModes: [.v5]
)
