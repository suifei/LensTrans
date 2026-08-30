import AppKit

// Entry stub. Not compiled on Windows. No Electron / Tauri.

@main
struct LensTransMacApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        _ = TrayController.shared
        if FirstRun.needsOnboarding {
            OnboardingWindow.present()
        }
        app.run()
    }
}

enum FirstRun {
    static var needsOnboarding: Bool { SettingsStore.shared.fileMissing }
}
