import AppKit

// Five-tab settings stub (通用 / 翻译 / 呈现 / 热键 / 关于). Not compiled on Windows.

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()
    var fileMissing: Bool { true }
    var downloadModel = true
    var autostart = false
}

@MainActor
enum SettingsWindow {
    static func present() {
        // TODO: NSTabView 5 tabs; persist next to Application Support/LensTrans.
        // Cloud Base URL / Key / Model stay empty. Keychain for key (see Secrets.swift).
        // Autostart: SMLoginItem or LaunchAgent — read system state, write/delete. Unimplemented.
    }
}
