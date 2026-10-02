// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexMeter", targets: ["CodexMeter"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexMeter",
            dependencies: [],
            resources: [
                .process("AppIcon.png"),
                .process("BrandIcon.png"),
                .process("PetAppIcon.png"),
                .process("appIcon2.png"),
                .copy("Pet"),
            ]
        ),
        .testTarget(
            name: "CodexMeterTests",
            dependencies: ["CodexMeter"]
        ),
    ]
)
