// swift-tools-version:5.9
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
        )
    ]
)
