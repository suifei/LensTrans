import AppKit

// NSStatusItem menu — parity with win/app/ui.cpp tray tree.

@MainActor
final class TrayController: NSObject {
    static let shared = TrayController()
    private var item: NSStatusItem?
    var enginePref: String = "auto"
    var targetLang: String = "zh"
    var contrastMode = false
    var onNewBox: (() -> Void)?
    var onToggleBoxes: (() -> Void)?
    var onPause: (() -> Void)?
    var onQuit: (() -> Void)?

    private override init() {
        super.init()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.title = "LT"
        rebuildMenu()
    }

    func rebuildMenu() {
        let m = NSMenu()
        m.addItem(menu("显示/隐藏全部翻译框", #selector(toggleBoxes)))
        m.addItem(menu("新建翻译框", #selector(newBox), key: "l"))
        m.addItem(.separator())
        m.addItem(menu("暂停/继续", #selector(pause), key: "t"))

        let eng = NSMenu()
        eng.addItem(menu("本地（快）", #selector(engLocal)))
        eng.addItem(menu("云端（强）", #selector(engCloud)))
        eng.addItem(menu("自动", #selector(engAuto)))
        let engItem = NSMenuItem(title: "翻译引擎", action: nil, keyEquivalent: "")
        engItem.submenu = eng
        m.addItem(engItem)

        let lang = NSMenu()
        lang.addItem(menu("简体中文", #selector(langZh)))
        lang.addItem(menu("English", #selector(langEn)))
        lang.addItem(menu("日本語", #selector(langJa)))
        lang.addItem(menu("한국어", #selector(langKo)))
        let langItem = NSMenuItem(title: "目标语言", action: nil, keyEquivalent: "")
        langItem.submenu = lang
        m.addItem(langItem)

        let mode = NSMenu()
        mode.addItem(menu("翻译", #selector(modeTrans)))
        mode.addItem(menu("对照", #selector(modeContrast)))
        let modeItem = NSMenuItem(title: "显示模式", action: nil, keyEquivalent: "")
        modeItem.submenu = mode
        m.addItem(modeItem)

        let autoItem = menu("开机自启", #selector(toggleAutostart))
        autoItem.state = MacSecrets.autostartEnabled() ? .on : .off
        m.addItem(autoItem)

        m.addItem(.separator())
        m.addItem(menu("设置…", #selector(openSettings), key: ","))
        m.addItem(menu("检查更新", #selector(checkUpdate)))
        m.addItem(menu("清理缓存", #selector(clearCache)))
        m.addItem(.separator())
        m.addItem(menu("退出", #selector(quit), key: "q"))
        item?.menu = m
    }

    private func menu(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleBoxes() {
        if let onToggleBoxes { onToggleBoxes() } else { OverlayBoxStore.shared.toggleAllVisible() }
    }

    @objc private func newBox() {
        if let onNewBox { onNewBox() } else { _ = OverlayBoxStore.shared.createBox() }
    }

    @objc private func pause() {
        if let onPause { onPause() } else { OverlayBoxStore.shared.pauseAll() }
    }

    @objc private func engLocal() { enginePref = "local"; SettingsStore.shared.engine = "local" }
    @objc private func engCloud() { enginePref = "cloud"; SettingsStore.shared.engine = "cloud" }
    @objc private func engAuto() { enginePref = "auto"; SettingsStore.shared.engine = "auto" }
    @objc private func langZh() { targetLang = "zh"; SettingsStore.shared.tgtLang = "zh" }
    @objc private func langEn() { targetLang = "en"; SettingsStore.shared.tgtLang = "en" }
    @objc private func langJa() { targetLang = "ja"; SettingsStore.shared.tgtLang = "ja" }
    @objc private func langKo() { targetLang = "ko"; SettingsStore.shared.tgtLang = "ko" }
    @objc private func modeTrans() { contrastMode = false; SettingsStore.shared.contrast = false }
    @objc private func modeContrast() { contrastMode = true; SettingsStore.shared.contrast = true }

    @objc private func toggleAutostart() {
        let next = !MacSecrets.autostartEnabled()
        MacSecrets.setAutostart(next)
        SettingsStore.shared.autostart = next
        rebuildMenu()
    }

    @objc private func openSettings() { SettingsWindow.present() }

    @objc private func checkUpdate() {
        let a = NSAlert()
        a.messageText = "检查更新"
        a.informativeText = "本版本不联网自动更新。当前 0.2 / Qwen2.5-0.5B Q4_K_M。"
        a.runModal()
    }

    @objc private func clearCache() { TranslationCacheStore.shared.clear() }

    @objc private func quit() {
        onQuit?()
        NSApp.terminate(nil)
    }
}

final class TranslationCacheStore {
    static let shared = TranslationCacheStore()
    private var map: [String: String] = [:]
    func get(_ key: String) -> String? { map[key] }
    func put(_ key: String, _ value: String) { map[key] = value }
    func clear() { map.removeAll() }
    var count: Int { map.count }
}
