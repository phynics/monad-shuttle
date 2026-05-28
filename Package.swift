// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shuttle",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "ShuttleWebUI", targets: ["ShuttleWebUI"]),
        .executable(name: "ShuttleServer", targets: ["ShuttleServer"]),
    ],
    dependencies: [
        .package(path: "../PositronicKit"),
    ],
    targets: [
        .executableTarget(
            name: "ShuttleServer",
            dependencies: [
                .product(name: "PositronicKit", package: "PositronicKit"),
                .product(name: "PKShared", package: "PositronicKit"),
            ],
            path: "Sources/ShuttleServer"
        ),
        .target(
            name: "ShuttleWebUI",
            path: "Sources/ShuttleWebUI"
        ),
        .testTarget(
            name: "ShuttleServerTests",
            dependencies: ["ShuttleServer"],
            path: "Tests/ShuttleServerTests"
        ),
        .testTarget(
            name: "ShuttleWebUITests",
            dependencies: ["ShuttleWebUI"],
            path: "Tests/ShuttleWebUITests"
        ),
    ]
)
