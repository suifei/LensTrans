import AppKit

// Entry. No Electron / Tauri. Accessory app with tray + optional onboarding.

@main
struct LensTransMacApp {
    static func main() {
        let app = NSApplication.shared
        let e2e = MacE2e.parse(Array(CommandLine.arguments.dropFirst()))
        if e2e.enabled {
            app.setActivationPolicy(.regular)
            Task { @MainActor in
                if e2e.noOnboard || FirstRun.needsOnboarding {
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
                if p.mode == .watching { p.enterEditing() } else { p.enterWatching() }
            }
        }
        HotkeyCenter.shared.onPause = { OverlayBoxStore.shared.pauseAll() }
        HotkeyCenter.shared.onHideAll = { OverlayBoxStore.shared.toggleAllVisible() }
        HotkeyCenter.shared.onSettings = { SettingsWindow.present() }
        HotkeyCenter.shared.installDefaults()

        TrayController.shared.onNewBox = { _ = OverlayBoxStore.shared.createBox() }
        TrayController.shared.onToggleBoxes = { OverlayBoxStore.shared.toggleAllVisible() }
        TrayController.shared.onPause = { OverlayBoxStore.shared.pauseAll() }

        if FirstRun.needsOnboarding {
            OnboardingWindow.present()
        } else {
            _ = OverlayBoxStore.shared.createBox()
        }
        app.run()
    }
}

@MainActor
enum FirstRun {
    static var needsOnboarding: Bool { SettingsStore.shared.fileMissing }
}
