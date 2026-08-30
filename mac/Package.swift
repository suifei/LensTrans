// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LensTransMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "LensTransLogic", targets: ["LensTransLogic"]),
        .executable(name: "LensTrans", targets: ["LensTransApp"]),
    ],
    targets: [
        .target(
            name: "LensTransLogic",
            path: "Logic"
        ),
        .executableTarget(
            name: "LensTransApp",
            dependencies: ["LensTransLogic"],
            path: ".",
            exclude: [
                "Logic",
                "Tests",
                "UNIMPLEMENTED.md",
                "Package.swift",
                "README.md",
                ".build",
            ],
            sources: [
                "App.swift",
                "Capture.swift",
                "Engine.swift",
                "Hotkeys.swift",
                "Ocr.swift",
                "Onboarding.swift",
                "OverlayPanel.swift",
                "Present.swift",
                "Secrets.swift",
                "Settings.swift",
                "Tray.swift",
            ]
        ),
        .testTarget(
            name: "LensTransLogicTests",
            dependencies: ["LensTransLogic"],
            path: "Tests"
        ),
    ]
)
