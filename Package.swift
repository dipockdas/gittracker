// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GitTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitTracker",
            path: "Sources",
            exclude: ["Resources/Info.plist"]
        ),
        .executableTarget(
            name: "gittracker-receiver",
            path: "Receiver",
            exclude: ["test-receiver.sh", "com.dipock.gittracker-receiver.plist"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
