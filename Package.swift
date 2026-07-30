// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PrimeTime",
    platforms: [
        // macOS 14 gives us MenuBarExtra + the Observation framework (@Observable).
        .macOS(.v14)
    ],
    dependencies: [
        // The local store (LocalBackend.swift): SQLite chosen over SwiftData
        // because GRDB records are plain Codable structs, so the existing
        // domain values persist without a mapping layer (see issue #23).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // In-app auto-update (issue #46). The SPM distribution is a prebuilt
        // XCFramework; bundle-app.sh copies it into Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "PrimeTime",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
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
        .testTarget(
            name: "PrimeTimeTests",
            // GRDB so tests can hand LocalBackend an in-memory DatabaseQueue
            // and inspect rows directly.
            dependencies: ["PrimeTime", .product(name: "GRDB", package: "GRDB.swift")],
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
