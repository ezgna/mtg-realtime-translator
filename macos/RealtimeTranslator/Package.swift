// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RealtimeTranslator",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "RealtimeTranslator", targets: ["RealtimeTranslator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.7"),
    ],
    targets: [
        .target(
            name: "RealtimeTranslatorCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .executableTarget(
            name: "RealtimeTranslator",
            dependencies: ["RealtimeTranslatorCore"]
        ),
        .testTarget(
            name: "RealtimeTranslatorCoreTests",
            dependencies: ["RealtimeTranslatorCore"]
        ),
    ]
)
