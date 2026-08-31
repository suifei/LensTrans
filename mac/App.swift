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
        TrayController.shared.onNewBox = { _ = OverlayBoxStore.shared.createBox() }
        TrayController.shared.onToggleBoxes = { OverlayBoxStore.shared.toggleAllVisible() }
        TrayController.shared.onToggleTranslation = { OverlayBoxStore.shared.toggleTranslation() }
        TrayController.shared.onPause = { OverlayBoxStore.shared.pauseAll() }

        let startWatching = argv.contains("--start-watching")
        if FirstRun.needsOnboarding && !noOnboard {
            OnboardingWindow.present()
        } else {
            if noOnboard && FirstRun.needsOnboarding {
                // Persist defaults so subsequent launches skip the wizard.
                SettingsStore.shared.downloadModel = false
                SettingsStore.shared.save()
            }
            _ = OverlayBoxStore.shared.createBox()
            if startWatching {
                for panel in OverlayBoxStore.shared.panels {
                    panel.enterWatching()
                }
            }
        }
        app.run()
    }
}

@MainActor
enum FirstRun {
    static var needsOnboarding: Bool { SettingsStore.shared.fileMissing }
}
