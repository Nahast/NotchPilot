// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NotchPilot",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NotchPilot", targets: ["NotchPilotApp"]),
        .executable(name: "notchpilot-hook", targets: ["NotchPilotHookHelper"]),
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .library(name: "ClaudeCodeProvider", targets: ["ClaudeCodeProvider"]),
        .library(name: "HookInstaller", targets: ["HookInstaller"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", exact: "1.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // MARK: Domain model
        .target(name: "AgentCore"),

        // MARK: Claude Code provider (transcripts + hook events)
        .target(
            name: "ClaudeCodeProvider",
            dependencies: ["AgentCore"]
        ),

        // MARK: ~/.claude/settings.json hook management
        .target(name: "HookInstaller"),

        // MARK: Session -> terminal/app focus
        .target(
            name: "JumpService",
            dependencies: ["AgentCore"]
        ),

        // MARK: UserDefaults-backed preferences
        .target(name: "SettingsStore"),

        // MARK: Notch UI (DynamicNotchKit wrapped behind NotchPresenter)
        .target(
            name: "NotchUI",
            dependencies: [
                "AgentCore",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ]
        ),

        // MARK: App
        .executableTarget(
            name: "NotchPilotApp",
            dependencies: [
                "AgentCore",
                "ClaudeCodeProvider",
                "HookInstaller",
                "JumpService",
                "SettingsStore",
                "NotchUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),

        // MARK: Hook micro-helper (Foundation only, must stay tiny and fast)
        .executableTarget(name: "NotchPilotHookHelper"),

        // MARK: Tests
        .testTarget(
            name: "AgentCoreTests",
            dependencies: ["AgentCore"]
        ),
        .testTarget(
            name: "ClaudeCodeProviderTests",
            dependencies: ["ClaudeCodeProvider", "AgentCore"]
        ),
        .testTarget(
            name: "HookInstallerTests",
            dependencies: ["HookInstaller"]
        ),
    ]
)
