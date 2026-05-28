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
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/jpsim/Yams", "5.4.0"..<"7.0.0"),
        .package(path: "../PositronicKit"),
    ],
    targets: [
        .executableTarget(
            name: "ShuttleServer",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "PositronicKit", package: "PositronicKit"),
                .product(name: "PKShared", package: "PositronicKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/ShuttleServer"
        ),
        .target(
            name: "ShuttleWebUI",
            path: "Sources/ShuttleWebUI"
        ),
        .testTarget(
            name: "ShuttleServerTests",
            dependencies: [
                "ShuttleServer",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/ShuttleServerTests"
        ),
        .testTarget(
            name: "ShuttleWebUITests",
            dependencies: ["ShuttleWebUI"],
            path: "Tests/ShuttleWebUITests"
        ),
    ]
)
