// swift-tools-version:6.2

import PackageDescription

// Forward-hardening upcoming-feature flags. All are already satisfied by the
// current source (it writes `any` everywhere and qualifies its imports), so
// enabling them locks in the style without code changes and surfaces any
// future regression as a build error.
//
// Deliberately NOT enabling MainActor default isolation: this is a library and
// must stay non-isolated so callers in any isolation domain can use it.
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

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
            resources: [.process("Resources")],
            swiftSettings: upcomingFeatures
        ),
        .testTarget(
            name: "DomainParserTests",
            dependencies: ["DomainParser"],
            swiftSettings: upcomingFeatures
        ),
    ]
)
