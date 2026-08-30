import AppKit

// NSStatusItem menu — parity with win/app/ui.cpp tray tree. Stub only.

@MainActor
final class TrayController {
    static let shared = TrayController()
    private var item: NSStatusItem?

    private init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.title = "LT"
        let m = NSMenu()
        m.addItem(withTitle: "显示/隐藏全部翻译框", action: nil, keyEquivalent: "")
        m.addItem(withTitle: "新建翻译框", action: nil, keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "暂停/继续", action: nil, keyEquivalent: "")
        let eng = NSMenu()
        eng.addItem(withTitle: "本地（快）", action: nil, keyEquivalent: "")
        eng.addItem(withTitle: "云端（强）", action: nil, keyEquivalent: "")
        eng.addItem(withTitle: "自动", action: nil, keyEquivalent: "")
        let engItem = NSMenuItem(title: "翻译引擎", action: nil, keyEquivalent: "")
        engItem.submenu = eng
        m.addItem(engItem)
        m.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        m.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item?.menu = m
    }

    @objc private func openSettings() {
        SettingsWindow.present()
    }
}
