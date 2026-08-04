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

        // MARK: Shared provider plumbing (FSEvents watching, JSONL tailing)
        .target(name: "ProviderCore"),

        // MARK: Claude Code provider (transcripts + hook events)
        .target(
            name: "ClaudeCodeProvider",
            dependencies: ["AgentCore", "ProviderCore"]
        ),

        // MARK: Codex (OpenAI) provider — rollout transcripts + session index
        .target(
            name: "CodexProvider",
            dependencies: ["AgentCore", "ProviderCore"]
        ),

        // MARK: Cursor provider — hooks.json events via the spool helper
        .target(
            name: "CursorProvider",
            dependencies: ["AgentCore", "ProviderCore"]
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
                "CodexProvider",
                "CursorProvider",
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
        .testTarget(
            name: "CodexProviderTests",
            dependencies: ["CodexProvider", "AgentCore"]
        ),
        .testTarget(
            name: "CursorProviderTests",
            dependencies: ["CursorProvider", "AgentCore"]
        ),
        .testTarget(
            name: "SettingsStoreTests",
            dependencies: ["SettingsStore"]
        ),
        .testTarget(
            name: "JumpServiceTests",
            dependencies: ["JumpService", "AgentCore"]
        ),
    ]
)
