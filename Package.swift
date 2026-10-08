// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TraceRook",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "TraceRook", targets: ["TraceRookApp"]),
        .executable(name: "TraceRookAgent", targets: ["TraceRookAgent"]),
        .executable(name: "tracerook-hook", targets: ["TraceRookHook"]),
        .library(name: "TraceRookContracts", targets: ["TraceRookContracts"]),
        .library(name: "TraceRookPrivacy", targets: ["TraceRookPrivacy"]),
        .library(name: "TraceRookAgentAdapters", targets: ["TraceRookAgentAdapters"]),
        .library(name: "TraceRookCore", targets: ["TraceRookCore"]),
        .library(name: "TraceRookIPC", targets: ["TraceRookIPC"]),
        .library(name: "TraceRookRules", targets: ["TraceRookRules"]),
        .library(name: "TraceRookFixtures", targets: ["TraceRookFixtures"])
    ],
    targets: [
        .target(name: "TraceRookContracts", path: "Packages/TraceRookContracts"),
        .target(name: "TraceRookPrivacy", dependencies: ["TraceRookContracts"], path: "Packages/TraceRookPrivacy"),
        .target(name: "TraceRookAgentAdapters", dependencies: ["TraceRookContracts", "TraceRookPrivacy"], path: "Packages/TraceRookAgentAdapters"),
        .target(name: "TraceRookRules", dependencies: ["TraceRookContracts"], path: "Packages/TraceRookRules"),
        .target(name: "TraceRookCore", dependencies: ["TraceRookContracts", "TraceRookPrivacy", "TraceRookRules"], path: "Packages/TraceRookCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "TraceRookIPC", dependencies: ["TraceRookContracts", "TraceRookCore"], path: "Packages/TraceRookIPC"),
        .target(name: "TraceRookFixtures", dependencies: ["TraceRookContracts", "TraceRookCore"], path: "Packages/TraceRookFixtures", resources: [.process("Resources")]),
        .executableTarget(name: "TraceRookApp", dependencies: ["TraceRookContracts", "TraceRookCore", "TraceRookPrivacy", "TraceRookFixtures", "TraceRookIPC"], path: "App"),
        .executableTarget(name: "TraceRookAgent", dependencies: ["TraceRookContracts", "TraceRookCore", "TraceRookFixtures", "TraceRookAgentAdapters", "TraceRookPrivacy", "TraceRookIPC"], path: "Agent"),
        .executableTarget(name: "TraceRookHook", dependencies: ["TraceRookContracts", "TraceRookAgentAdapters", "TraceRookRules", "TraceRookIPC"], path: "HookCLI"),
        .testTarget(name: "ContractsTests", dependencies: ["TraceRookContracts", "TraceRookFixtures"], path: "Tests/ContractsTests"),
        .testTarget(name: "PrivacyTests", dependencies: ["TraceRookPrivacy"], path: "Tests/PrivacyTests"),
        .testTarget(name: "AdapterTests", dependencies: ["TraceRookAgentAdapters", "TraceRookFixtures"], path: "Tests/AdapterTests"),
        .testTarget(name: "CoreTests", dependencies: ["TraceRookCore", "TraceRookFixtures"], path: "Tests/CoreTests"),
        .testTarget(name: "UIBasicTests", dependencies: ["TraceRookCore", "TraceRookFixtures"], path: "Tests/UIBasicTests"),
        .testTarget(name: "ServiceTests", dependencies: ["TraceRookCore", "TraceRookContracts", "TraceRookIPC", "TraceRookFixtures"], path: "Tests/ServiceTests"),
        .testTarget(name: "RulesTests", dependencies: ["TraceRookRules", "TraceRookContracts"], path: "Tests/RulesTests")
    ],
    swiftLanguageModes: [.v6]
)
