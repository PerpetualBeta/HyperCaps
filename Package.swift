// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyperCaps",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HyperCaps",
            path: "Sources",
            linkerSettings: [
                .unsafeFlags(["-framework", "AppKit"]),
                .unsafeFlags(["-framework", "ApplicationServices"]),
                .unsafeFlags(["-framework", "IOKit"]),
                .unsafeFlags(["-framework", "ServiceManagement"]),
            ]
        )
    ]
)
