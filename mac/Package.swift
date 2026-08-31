// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let llamaSrc = (packageDir as NSString).appendingPathComponent("../third_party/llama.cpp")
let llamaBin = (llamaSrc as NSString).appendingPathComponent("build/bin")
let llamaHeader = (llamaSrc as NSString).appendingPathComponent("include/llama.h")
let llamaDylib = (llamaBin as NSString).appendingPathComponent("libllama.dylib")
let hasLlama =
    FileManager.default.fileExists(atPath: llamaHeader)
    && FileManager.default.fileExists(atPath: llamaDylib)

let logicTargets: [Target] = [
    .target(name: "LensTransLogic", path: "Logic"),
    .testTarget(name: "LensTransLogicTests", dependencies: ["LensTransLogic"], path: "Tests"),
]

#if os(macOS)

var llamaCxxSettings: [CXXSetting] = [
    .unsafeFlags(["-std=c++17"]),
    .unsafeFlags(["-I\(packageDir)/../core/include"]),
]
var llamaLinkerSettings: [LinkerSetting] = []
var appLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("Accelerate"),
    .linkedFramework("Foundation"),
]

if hasLlama {
    llamaCxxSettings.append(contentsOf: [
        .define("LENSTRANS_WITH_LLAMA"),
        .unsafeFlags([
            "-I\(llamaSrc)/include",
            "-I\(llamaSrc)/ggml/include",
        ]),
    ])
    // Link Metal llama.cpp shared libs; rpath covers both third_party (dev) and .app Frameworks.
    appLinkerSettings.append(contentsOf: [
        .unsafeFlags([
            "-L\(llamaBin)",
            "-lllama",
            "-lggml",
            "-lggml-base",
            "-lggml-cpu",
            "-lggml-blas",
            "-lggml-metal",
            "-Xlinker", "-rpath", "-Xlinker", llamaBin,
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
            "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Resources/bin",
        ]),
    ])
}

let package = Package(
    name: "LensTransMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LensTransLogic", targets: ["LensTransLogic"]),
        .executable(name: "LensTrans", targets: ["LensTransApp"]),
    ],
    targets: logicTargets + [
        .target(
            name: "LlamaBridge",
            path: "Native",
            publicHeadersPath: "include",
            cxxSettings: llamaCxxSettings,
            linkerSettings: llamaLinkerSettings
        ),
        .executableTarget(
            name: "LensTransApp",
            dependencies: ["LensTransLogic", "LlamaBridge"],
            path: ".",
            exclude: [
                "Logic",
                "Tests",
                "Native",
                "UNIMPLEMENTED.md",
                "Package.swift",
                "README.md",
                "Info.plist",
                ".build",
            ],
            sources: [
                "App.swift",
                "Capture.swift",
                "CoreBridge.swift",
                "E2e.swift",
                "Engine.swift",
                "Ocr.swift",
                "Onboarding.swift",
                "OverlayPanel.swift",
                "Pipeline.swift",
                "Present.swift",
                "Secrets.swift",
                "Settings.swift",
                "Tray.swift",
            ],
            linkerSettings: appLinkerSettings
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
