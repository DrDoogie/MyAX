// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingRecorder",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MeetingRecorder", targets: ["MeetingRecorder"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MeetingRecorder",
            dependencies: [],
            path: "Sources/MeetingRecorder",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MeetingRecorderTests",
            dependencies: ["MeetingRecorder"],
            path: "Tests"
        )
    ]
)
