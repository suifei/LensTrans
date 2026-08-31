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
    var onTranslationStart: (() -> Void)?
    var onTranslationStop: (() -> Void)?

    private let gestureKeyCode = UInt16(kVK_Space)
    private let gestureModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private let doubleTapWindow: TimeInterval = 0.5
    private var globalGestureMonitor: Any?
    private var localGestureMonitor: Any?
    private var gestureStopTask: Task<Void, Never>?
    private var gestureKeyDown = false
    private var gestureLocked = false
    private var lockedTapPending = false
    private var lastGestureUp = Date.distantPast

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
        installGestureMonitors()
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
            let hotKeyID = EventHotKeyID(signature: OSType(0x4C545348), id: UInt32(c.id)) // 'LTSH'
            RegisterEventHotKey(c.key, c.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func unregisterAll() {
        gestureStopTask?.cancel()
        gestureStopTask = nil
        if let monitor = globalGestureMonitor {
            NSEvent.removeMonitor(monitor)
            globalGestureMonitor = nil
        }
        if let monitor = localGestureMonitor {
            NSEvent.removeMonitor(monitor)
            localGestureMonitor = nil
        }
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installGestureMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        globalGestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) {
            [weak self] event in
            Task { @MainActor in self?.handleGesture(event) }
        }
        localGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) {
            [weak self] event in
            Task { @MainActor in self?.handleGesture(event) }
            return event
        }
    }

    private func handleGesture(_ event: NSEvent) {
        guard event.keyCode == gestureKeyCode else { return }
        switch event.type {
        case .keyDown:
            guard !event.isARepeat, !gestureKeyDown,
                  event.modifierFlags.intersection([.command, .shift]) == gestureModifiers else {
                return
            }
            gestureKeyDown = true
            let now = Date()
            if gestureLocked {
                if lockedTapPending && now.timeIntervalSince(lastGestureUp) <= doubleTapWindow {
                    gestureLocked = false
                    lockedTapPending = false
                    onTranslationStop?()
                } else {
                    lockedTapPending = true
                    lastGestureUp = now
                }
            } else if now.timeIntervalSince(lastGestureUp) <= doubleTapWindow {
                gestureStopTask?.cancel()
                gestureLocked = true
                lockedTapPending = false
                lastGestureUp = .distantPast
                onTranslationStart?()
            } else {
                onTranslationStart?()
            }
        case .keyUp:
            guard gestureKeyDown else { return }
            gestureKeyDown = false
            if gestureLocked {
                if lockedTapPending { lastGestureUp = Date() }
                return
            }
            lastGestureUp = Date()
            gestureStopTask?.cancel()
            gestureStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 520_000_000)
                guard let self, !Task.isCancelled, !self.gestureKeyDown,
                      !self.gestureLocked else { return }
                self.lastGestureUp = .distantPast
                self.onTranslationStop?()
            }
        default:
            break
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
