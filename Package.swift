// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TraggoMenuBar",
    platforms: [
        // macOS 14 gives us MenuBarExtra + the Observation framework (@Observable).
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TraggoMenuBar",
            path: "Sources/TraggoMenuBar"
        ),
        .testTarget(
            name: "TraggoMenuBarTests",
            dependencies: ["TraggoMenuBar"],
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
