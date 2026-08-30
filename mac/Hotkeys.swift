import AppKit
import Carbon.HIToolbox

// Global hotkeys — parity with RegisterHotKey + click-to-record in Settings.

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    struct Combo {
        var id: Int
        var modifiers: UInt32
        var key: UInt32
        var handler: () -> Void
    }

    var combos: [Combo] = []
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    var onEditToggle: (() -> Void)?
    var onNewBox: (() -> Void)?
    var onPause: (() -> Void)?
    var onHideAll: (() -> Void)?
    var onSettings: (() -> Void)?

    func installDefaults() {
        combos = [
            Combo(id: 1, modifiers: UInt32(cmdKey | shiftKey), key: UInt32(kVK_ANSI_L),
                  handler: { [weak self] in self?.onNewBox?() }),
            Combo(id: 2, modifiers: UInt32(cmdKey), key: UInt32(kVK_ANSI_E),
                  handler: { [weak self] in self?.onEditToggle?() }),
            Combo(id: 3, modifiers: UInt32(cmdKey), key: UInt32(kVK_ANSI_T),
                  handler: { [weak self] in self?.onPause?() }),
            Combo(id: 4, modifiers: UInt32(cmdKey | shiftKey), key: UInt32(kVK_ANSI_H),
                  handler: { [weak self] in self?.onHideAll?() }),
            Combo(id: 5, modifiers: UInt32(cmdKey), key: UInt32(kVK_ANSI_Comma),
                  handler: { [weak self] in self?.onSettings?() }),
        ]
        registerAll()
    }

    func registerAll() {
        unregisterAll()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData else { return noErr }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                              nil, &hotKeyID)
            if let combo = center.combos.first(where: { $0.id == Int(hotKeyID.id) }) {
                DispatchQueue.main.async { combo.handler() }
            }
            return noErr
        }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandler)

        guard status == noErr else { return }
        for c in combos {
            var ref: EventHotKeyRef?
            var hotKeyID = EventHotKeyID(signature: OSType(0x4C545348), id: UInt32(c.id)) // 'LTSH'
            RegisterEventHotKey(c.key, c.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Click-to-record helper used by Settings 热键 tab.
    static func format(modifiers: UInt32, key: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "Ctrl+" }
        if modifiers & UInt32(optionKey) != 0 { s += "Opt+" }
        if modifiers & UInt32(shiftKey) != 0 { s += "Shift+" }
        if modifiers & UInt32(cmdKey) != 0 { s += "Cmd+" }
        s += keyName(key)
        return s
    }

    private static func keyName(_ key: UInt32) -> String {
        switch Int(key) {
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_Comma: return ","
        default: return "VK\(key)"
        }
    }
}
