// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "netScope",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "netScope", targets: ["netScope"]),
        .executable(name: "NetScopeMenuBar", targets: ["NetScopeMenuBar"]),
        .library(name: "NetScopeCore", targets: ["NetScopeCore"]),
    ],
    targets: [
        .target(
            name: "NetScopeCore"
        ),
        .executableTarget(
            name: "netScope",
            dependencies: ["NetScopeCore"]
        ),
        .executableTarget(
            name: "NetScopeMenuBar",
            dependencies: ["NetScopeCore"]
        ),
        .testTarget(
            name: "NetScopeCoreTests",
            dependencies: ["NetScopeCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
