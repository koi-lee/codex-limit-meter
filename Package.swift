// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CodexLimitMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexLimitMeter", targets: ["CodexLimitMeter"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexLimitMeter",
            dependencies: [],
            resources: [
                .process("AppIcon.png"),
                .process("appIcon2.png"),
            ]
        ),
        .testTarget(
            name: "CodexLimitMeterTests",
            dependencies: ["CodexLimitMeter"]
        ),
    ]
)
