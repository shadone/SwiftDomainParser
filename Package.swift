// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "DomainParser",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DomainParser", targets: ["DomainParser"]),
    ],
    targets: [
        .target(
            name: "DomainParser",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DomainParserTests",
            dependencies: ["DomainParser"]
        ),
    ]
)
