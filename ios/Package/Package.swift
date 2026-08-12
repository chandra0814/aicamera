// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "LensPilot",
    platforms: [
        .iOS(.v17),
        .macOS(.v12)
    ],
    products: [
        .library(name: "LensPilotCore", targets: ["LensPilotCore"]),
        .library(name: "LensPilotCamera", targets: ["LensPilotCamera"]),
        .library(name: "LensPilotVision", targets: ["LensPilotVision"]),
        .library(name: "LensPilotDirector", targets: ["LensPilotDirector"])
    ],
    targets: [
        .target(name: "LensPilotCore"),
        .target(name: "LensPilotCamera", dependencies: ["LensPilotCore"]),
        .target(name: "LensPilotVision", dependencies: ["LensPilotCore"]),
        .target(name: "LensPilotDirector", dependencies: ["LensPilotCore"]),
        .testTarget(name: "LensPilotCoreTests", dependencies: ["LensPilotCore"])
    ]
)
