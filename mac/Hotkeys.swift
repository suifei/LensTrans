import AppKit
import Carbon.HIToolbox

// Global hotkeys — parity with RegisterHotKey. Stub.

@MainActor
final class HotkeyCenter {
    var combos: [(id: Int, modifiers: UInt32, key: UInt32)] = [
        (1, UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_L)),
        (2, UInt32(cmdKey), UInt32(kVK_ANSI_E)),
        (3, UInt32(cmdKey), UInt32(kVK_ANSI_T)),
        (4, UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_H)),
        (5, UInt32(cmdKey), UInt32(kVK_ANSI_Comma)),
    ]

    func registerAll() {
        // TODO: EventHotKey / NSEvent.addGlobalMonitor. Click-to-record in Settings 热键 tab.
    }

    func unregisterAll() {}
}
