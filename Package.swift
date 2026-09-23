// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalResearchAgent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PersonalResearchAgent",
            targets: ["PersonalResearchAgent"]
        ),
        .executable(
            name: "TestRunner",
            targets: ["TestRunner"]
        )
    ],
    targets: [
        .target(
            name: "PersonalResearchAgentCore",
            path: "Sources/PersonalResearchAgentCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "PersonalResearchAgent",
            dependencies: ["PersonalResearchAgentCore"],
            path: "Sources/PersonalResearchAgent",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["PersonalResearchAgentCore"],
            path: "Tests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
