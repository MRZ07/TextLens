// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TextLensCore", targets: ["TextLensCore"]),
        .executable(name: "TextLensApp", targets: ["TextLensApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(name: "TextLensCore"),
        .executableTarget(
            name: "TextLensApp",
            dependencies: [
                "TextLensCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/TextLensApp"
        ),
        .testTarget(name: "TextLensCoreTests", dependencies: ["TextLensCore"]),
        .testTarget(
            name: "TextLensAppTests",
            dependencies: ["TextLensApp", "TextLensCore"]
        ),
    ]
)
