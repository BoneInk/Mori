// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mirror",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mirror", targets: ["Mirror"])
    ],
    targets: [
        .executableTarget(
            name: "Mirror",
            path: "Sources/Mirror",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Quartz"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
