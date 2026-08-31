import AppKit

// Five-tab settings (通用 / 翻译 / 呈现 / 热键 / 关于). Persist under Application Support.

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    var fileMissing: Bool {
        !FileManager.default.fileExists(atPath: settingsURL.path)
    }

    var downloadModel = true
    var autostart = false
    var engine = "auto"
    var tgtLang = "zh"
    var contrast = false
    var render = "auto"
    var stickerAlpha = 92
    var fontScale = 100
    var cloudBaseURL = ""
    var cloudModel = ""
    var modelPath = ""
    var quality = false

    private init() { load() }

    var settingsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("LensTrans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.cfg")
    }

    var modelsDir: URL {
        let dir = settingsURL.deletingLastPathComponent().appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func load() {
        guard let text = try? String(contentsOf: settingsURL, encoding: .utf8) else { return }
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eq])
            let v = String(line[line.index(after: eq)...])
            switch k {
            case "download_model": downloadModel = v == "1"
            case "autostart": autostart = v == "1"
            case "engine": engine = v
            case "tgt_lang": tgtLang = v
            case "contrast": contrast = v == "1"
            case "render": render = v
            case "sticker_alpha": stickerAlpha = Int(v) ?? 92
            case "font_scale": fontScale = Int(v) ?? 100
            case "cloud_base_url": cloudBaseURL = v
            case "cloud_model": cloudModel = v
            case "model_path": modelPath = v
            case "quality": quality = v == "1"
            default: break
            }
        }
    }

    func save() {
        // api_key never written here — Keychain only.
        let body = """
        engine=\(engine)
        download_model=\(downloadModel ? 1 : 0)
        autostart=\(autostart ? 1 : 0)
        tgt_lang=\(tgtLang)
        contrast=\(contrast ? 1 : 0)
        render=\(render)
        sticker_alpha=\(stickerAlpha)
        font_scale=\(fontScale)
        cloud_base_url=\(cloudBaseURL)
        cloud_model=\(cloudModel)
        model_path=\(modelPath)
        quality=\(quality ? 1 : 0)
        """
        try? body.write(to: settingsURL, atomically: true, encoding: .utf8)
        MacSecrets.setAutostart(autostart)
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var fields = SettingsFields()

    static func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let store = SettingsStore.shared
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "LensTrans 设置"
        win.center()

        var f = SettingsFields()
        let tab = NSTabView(frame: NSRect(x: 12, y: 48, width: 496, height: 340))
        tab.addTabViewItem(makeTab("通用", buildGeneral(store, &f)))
        tab.addTabViewItem(makeTab("翻译", buildTranslate(store, &f)))
        tab.addTabViewItem(makeTab("呈现", buildPresent(store, &f)))
        tab.addTabViewItem(makeTab("热键", buildHotkeys()))
        tab.addTabViewItem(makeTab("关于", buildAbout()))
        fields = f

        let save = NSButton(title: "保存", target: SettingsSaveTarget.shared, action: #selector(SettingsSaveTarget.save))
        save.frame = NSRect(x: 400, y: 12, width: 80, height: 28)
        save.keyEquivalent = "\r"
        SettingsSaveTarget.shared.onSave = {
            applyFields()
            store.save()
            win.close()
            SettingsWindow.window = nil
        }

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        root.addSubview(tab)
        root.addSubview(save)
        win.contentView = root
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    private static func applyFields() {
        let s = SettingsStore.shared
        let f = fields
        if let b = f.autostart { s.autostart = b.state == .on }
        if let b = f.download { s.downloadModel = b.state == .on }
        if let b = f.contrast { s.contrast = b.state == .on }
        if let t = f.baseField { s.cloudBaseURL = t.stringValue.trimmingCharacters(in: .whitespaces) }
        if let t = f.modelField { s.cloudModel = t.stringValue.trimmingCharacters(in: .whitespaces) }
        if let t = f.keyField { try? MacSecrets.saveCloudKey(t.stringValue) }
    }

    private static func makeTab(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private static func buildGeneral(_ s: SettingsStore, _ f: inout SettingsFields) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        let auto = NSButton(checkboxWithTitle: "开机自启", target: nil, action: nil)
        auto.state = s.autostart ? .on : .off
        auto.frame = NSRect(x: 16, y: 220, width: 200, height: 24)
        f.autostart = auto
        v.addSubview(auto)
        let dl = NSButton(checkboxWithTitle: "使用本地模型（推荐）", target: nil, action: nil)
        dl.state = s.downloadModel ? .on : .off
        dl.frame = NSRect(x: 16, y: 180, width: 240, height: 24)
        f.download = dl
        v.addSubview(dl)
        return v
    }

    private static func buildTranslate(_ s: SettingsStore, _ f: inout SettingsFields) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        let base = labeledField("Base URL", s.cloudBaseURL, y: 210)
        let model = labeledField("Model", s.cloudModel, y: 160)
        let key = labeledField("API Key", MacSecrets.loadCloudKey(), y: 110, secure: true)
        f.baseField = base.1
        f.modelField = model.1
        f.keyField = key.1
        v.addSubview(base.0); v.addSubview(base.1)
        v.addSubview(model.0); v.addSubview(model.1)
        v.addSubview(key.0); v.addSubview(key.1)
        let note = NSTextField(labelWithString: "三项全空则禁用云端。密钥只进 Keychain，不写入 settings.cfg。")
        note.frame = NSRect(x: 16, y: 60, width: 440, height: 40)
        note.font = .systemFont(ofSize: 11)
        v.addSubview(note)
        return v
    }

    private static func buildPresent(_ s: SettingsStore, _ f: inout SettingsFields) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        let note = NSTextField(labelWithString: "呈现：沉浸替换 / 贴条盖原文。禁止半透明叠字。")
        note.frame = NSRect(x: 16, y: 220, width: 440, height: 24)
        v.addSubview(note)
        let contrast = NSButton(checkboxWithTitle: "对照模式（贴条下显示原文）", target: nil, action: nil)
        contrast.state = s.contrast ? .on : .off
        contrast.frame = NSRect(x: 16, y: 180, width: 280, height: 24)
        f.contrast = contrast
        v.addSubview(contrast)
        return v
    }

    private static func buildHotkeys() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        let lines = ["⌘⇧L 新建框", "⌘E 编辑/穿透", "⌘T 暂停", "⌘⇧H 全隐", "⌘, 设置"]
        for (i, line) in lines.enumerated() {
            let l = NSTextField(labelWithString: line)
            l.frame = NSRect(x: 16, y: 220 - i * 28, width: 400, height: 24)
            v.addSubview(l)
        }
        return v
    }

    private static func buildAbout() -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        let l = NSTextField(wrappingLabelWithString:
            "LensTrans 0.2\n默认模型 Qwen2.5-0.5B Instruct Q4_K_M\nApache-2.0 可覆盖 EU/UK/KR\n无 Electron / Tauri / Hunyuan")
        l.frame = NSRect(x: 16, y: 120, width: 440, height: 120)
        v.addSubview(l)
        return v
    }

    private static func labeledField(_ title: String, _ value: String, y: CGFloat, secure: Bool = false)
        -> (NSTextField, NSTextField) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 16, y: y + 24, width: 120, height: 18)
        let field: NSTextField = secure ? NSSecureTextField(frame: .zero) : NSTextField(frame: .zero)
        field.stringValue = value
        field.frame = NSRect(x: 16, y: y, width: 440, height: 24)
        return (label, field)
    }
}

private struct SettingsFields {
    var autostart: NSButton?
    var download: NSButton?
    var contrast: NSButton?
    var baseField: NSTextField?
    var modelField: NSTextField?
    var keyField: NSTextField?
}

@MainActor
private final class SettingsSaveTarget: NSObject {
    static let shared = SettingsSaveTarget()
    var onSave: (() -> Void)?
    @objc func save() { onSave?() }
}
