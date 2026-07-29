// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TraggoMenuBar",
    platforms: [
        // macOS 14 gives us MenuBarExtra + the Observation framework (@Observable).
        .macOS(.v14)
    ],
    dependencies: [
        // The local store (LocalBackend.swift): SQLite chosen over SwiftData
        // because GRDB records are plain Codable structs, so the existing
        // domain values persist without a mapping layer (see issue #23).
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TraggoMenuBar",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/TraggoMenuBar"
        ),
        .testTarget(
            name: "TraggoMenuBarTests",
            // GRDB so tests can hand LocalBackend an in-memory DatabaseQueue
            // and inspect rows directly.
            dependencies: ["TraggoMenuBar", .product(name: "GRDB", package: "GRDB.swift")],
            path: "Tests/TraggoMenuBarTests"
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
