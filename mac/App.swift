import AppKit

// Entry. No Electron / Tauri. Accessory app with tray + optional onboarding.

@main
struct LensTransMacApp {
    static func main() {
        let app = NSApplication.shared
        let argv = Array(CommandLine.arguments.dropFirst())
        let e2e = MacE2e.parse(argv)
        let noOnboard = e2e.noOnboard || argv.contains("--no-onboard")
        if e2e.enabled {
            app.setActivationPolicy(.regular)
            Task { @MainActor in
                if noOnboard || FirstRun.needsOnboarding {
                    SettingsStore.shared.downloadModel = false
                    SettingsStore.shared.save()
                }
                let code = await MacE2e.run(e2e)
                exit(code)
            }
            app.run()
            return
        }

        app.setActivationPolicy(.accessory)
        _ = TrayController.shared
        HotkeyCenter.shared.onNewBox = { _ = OverlayBoxStore.shared.createBox() }
        HotkeyCenter.shared.onEditToggle = {
            for p in OverlayBoxStore.shared.panels {
                switch p.mode {
                case .watching, .translating, .paused:
                    p.enterEditing()
                case .editing, .hidden:
                    p.enterWatching()
                }
            }
        }
        HotkeyCenter.shared.onPause = { OverlayBoxStore.shared.pauseAll() }
        HotkeyCenter.shared.onHideAll = { OverlayBoxStore.shared.toggleAllVisible() }
        HotkeyCenter.shared.onSettings = { SettingsWindow.present() }
        HotkeyCenter.shared.installDefaults()

        TrayController.shared.onNewBox = { _ = OverlayBoxStore.shared.createBox() }
        TrayController.shared.onToggleBoxes = { OverlayBoxStore.shared.toggleAllVisible() }
        TrayController.shared.onPause = { OverlayBoxStore.shared.pauseAll() }

        if FirstRun.needsOnboarding && !noOnboard {
            OnboardingWindow.present()
        } else {
            if noOnboard && FirstRun.needsOnboarding {
                // Persist defaults so subsequent launches skip the wizard.
                SettingsStore.shared.downloadModel = false
                SettingsStore.shared.save()
            }
            _ = OverlayBoxStore.shared.createBox()
        }
        app.run()
    }
}

@MainActor
enum FirstRun {
    static var needsOnboarding: Bool { SettingsStore.shared.fileMissing }
}
