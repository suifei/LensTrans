// swift-tools-version: 5.9
import PackageDescription

let logicTargets: [Target] = [
    .target(name: "LensTransLogic", path: "Logic"),
    .testTarget(name: "LensTransLogicTests", dependencies: ["LensTransLogic"], path: "Tests"),
]

#if os(macOS)
let package = Package(
    name: "LensTransMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LensTransLogic", targets: ["LensTransLogic"]),
        .executable(name: "LensTrans", targets: ["LensTransApp"]),
    ],
    targets: logicTargets + [
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
                "Info.plist",
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
                "Pipeline.swift",
                "Present.swift",
                "Secrets.swift",
                "Settings.swift",
                "Tray.swift",
            ]
        ),
    ]
)
#else
// Linux CI: Logic + tests only (no AppKit / ScreenCaptureKit).
let package = Package(
    name: "LensTransMac",
    products: [
        .library(name: "LensTransLogic", targets: ["LensTransLogic"]),
    ],
    targets: logicTargets
)
#endif
