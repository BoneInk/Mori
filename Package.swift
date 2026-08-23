// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mori",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mori", targets: ["Mori"])
    ],
    targets: [
        .executableTarget(
            name: "Mori",
            path: "Sources/Mori",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Quartz"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
