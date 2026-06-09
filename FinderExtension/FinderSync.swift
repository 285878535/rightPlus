//
//  FinderSync.swift
//  FinderExtension
//
//  superMouse —— 增强 macOS 右键菜单：剪切、复制、粘贴、新建文本文件、在终端中打开
//

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    // 内存缓存：避免每次右键读盘 + 现算图标（按配置文件修改时间判断是否刷新）
    private var cachedConfig = SuperMouseConfig.default
    private var configMTime: Date?
    private var iconCache: [String: NSImage] = [:]

    override init() {
        super.init()
        // 监听整个文件系统，使菜单在所有文件夹中生效
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        refreshConfigIfNeeded(force: true)
    }

    /// 仅在配置文件变更时重新读盘并清空内存图标缓存；图标按需懒加载（见 icon(for:)），不阻塞启动
    private func refreshConfigIfNeeded(force: Bool = false) {
        let mtime = SharedStore.configURL.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
        } ?? nil
        guard force || mtime != configMTime else { return }
        cachedConfig = ConfigStore.load()
        configMTime = mtime
        iconCache.removeAll(keepingCapacity: true)
    }

    /// 取模板图标：内存缓存 → 磁盘缓存（跨进程复用）→ 现算系统图标并预栅格化落盘
    private func icon(for t: FileTemplate) -> NSImage? {
        let key = t.suffix.isEmpty ? "_plain" : t.suffix.lowercased()
        if let cached = iconCache[key] { return cached }

        let diskURL = SharedStore.iconCacheDir?.appendingPathComponent("\(key).png")
        if let diskURL, let img = NSImage(contentsOf: diskURL) {
            img.size = NSSize(width: 16, height: 16)
            iconCache[key] = img
            return img
        }

        // 把系统图标（含多分辨率大图）预渲染成 16pt@2x 单一位图：冷启动只算一次、菜单绘制也更快
        let rep = rasterize(t.icon)
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.addRepresentation(rep)
        iconCache[key] = img
        if let diskURL, let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: diskURL)
        }
        return img
    }

    /// 将任意 NSImage 渲染为 32×32 像素（16pt@2x，覆盖 Retina）的位图
    private func rasterize(_ source: NSImage) -> NSBitmapImageRep {
        let px = 32
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 16, height: 16)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        refreshConfigIfNeeded()
        let cfg = cachedConfig

        switch menuKind {
        case .contextualMenuForItems:
            // 右键点在选中的文件/文件夹上
            if cfg.enableCut { addItem(menu, "剪切", #selector(cut(_:))) }
            if cfg.enableCopy { addItem(menu, "复制", #selector(copyItems(_:))) }
            if cfg.enableAirDrop { addItem(menu, "隔空投送", #selector(airDrop(_:))) }

        case .contextualMenuForContainer:
            // 右键点在文件夹空白处（当前文件夹）
            addNewFileMenu(to: menu, config: cfg)
            if cfg.enablePaste && hasClipboard() {
                addItem(menu, "粘贴", #selector(paste(_:)))
            }
            if cfg.enableTerminal {
                addItem(menu, "在终端中打开", #selector(openInTerminal(_:)))
            }

        default:
            break
        }
        return menu
    }

    /// 根据配置生成「新建」子菜单 + 主菜单直显项
    private func addNewFileMenu(to menu: NSMenu, config: SuperMouseConfig) {
        // 用 tag 携带模板在 config.templates 中的下标（FinderSync 下 representedObject 不保留，tag 保留）
        let indexed = config.templates.enumerated().filter { $0.element.enabled }
        guard !indexed.isEmpty else { return }

        let newRoot = NSMenuItem(title: "新建", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "新建")
        submenu.autoenablesItems = false
        for (idx, t) in indexed {
            submenu.addItem(makeNewItem(title: t.name, tag: idx, icon: config.showIcon ? icon(for: t) : nil))
        }
        newRoot.submenu = submenu
        menu.addItem(newRoot)

        // 标记「主菜单」的项，额外直接显示在顶层
        for (idx, t) in indexed where t.inMainMenu {
            menu.addItem(makeNewItem(title: "新建\(t.name)", tag: idx, icon: config.showIcon ? icon(for: t) : nil))
        }
    }

    private func makeNewItem(title: String, tag: Int, icon: NSImage?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(newFromTemplate(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        if let icon {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        return item
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - 安全作用域访问
    //
    // 沙盒下，FinderSync 给的 URL 必须 startAccessingSecurityScopedResource 才能读写；
    // 剪切→粘贴跨操作要用安全作用域书签保存授权（普通路径会丢失访问权）。

    @discardableResult
    private func withAccess<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    // MARK: - 剪贴板（安全作用域书签，存于扩展容器）

    private struct Clipboard: Codable {
        var bookmarks: [Data]
        var isCut: Bool
    }

    private var clipboardURL: URL {
        SharedStore.baseDir.appendingPathComponent("clipboard.json")
    }

    private func saveClipboard(_ urls: [URL], isCut: Bool) {
        let bookmarks: [Data] = urls.compactMap { url in
            withAccess(url) {
                try? url.bookmarkData(options: [.withSecurityScope],
                                      includingResourceValuesForKeys: nil,
                                      relativeTo: nil)
            }
        }
        guard !bookmarks.isEmpty,
              let data = try? JSONEncoder().encode(Clipboard(bookmarks: bookmarks, isCut: isCut))
        else { return }
        try? data.write(to: clipboardURL)
    }

    private func loadClipboard() -> Clipboard? {
        guard let data = try? Data(contentsOf: clipboardURL),
              let cb = try? JSONDecoder().decode(Clipboard.self, from: data),
              !cb.bookmarks.isEmpty else { return nil }
        return cb
    }

    // 仅判断剪贴板文件是否存在——saveClipboard 只在书签非空时写入、cut→paste 后清除，
    // 因此「存在」即「有效」，省去每次右键的读盘 + JSON 解码
    private func hasClipboard() -> Bool {
        FileManager.default.fileExists(atPath: clipboardURL.path)
    }

    private func clearClipboard() {
        try? FileManager.default.removeItem(at: clipboardURL)
    }

    // MARK: - 当前文件夹

    private var targetFolder: URL? {
        FIFinderSyncController.default().targetedURL()
    }

    // MARK: - 操作

    @objc func cut(_ sender: AnyObject?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        saveClipboard(urls, isCut: true)
    }

    @objc func copyItems(_ sender: AnyObject?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        saveClipboard(urls, isCut: false)
    }

    @objc func airDrop(_ sender: AnyObject?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        // 扩展无窗口，弹不出 AirDrop 面板 —— 写文件清单后唤起主 App（rightplus://airdrop）执行
        let paths = urls.map { $0.path }
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: SharedStore.baseDir.appendingPathComponent("airdrop.json"))
        }
        if let url = URL(string: "rightplus://airdrop") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func paste(_ sender: AnyObject?) {
        guard let cb = loadClipboard(), let dest = targetFolder else { return }
        let fm = FileManager.default
        withAccess(dest) {
            for bm in cb.bookmarks {
                var stale = false
                guard let src = try? URL(resolvingBookmarkData: bm,
                                         options: [.withSecurityScope],
                                         relativeTo: nil,
                                         bookmarkDataIsStale: &stale) else { continue }
                withAccess(src) {
                    guard fm.fileExists(atPath: src.path) else { return }
                    let target = uniqueDestination(for: src.lastPathComponent, in: dest)
                    do {
                        if cb.isCut {
                            try fm.moveItem(at: src, to: target)
                        } else {
                            try fm.copyItem(at: src, to: target)
                        }
                    } catch {
                        NSLog("superMouse 粘贴失败: \(error)")
                    }
                }
            }
        }
        if cb.isCut { clearClipboard() }
    }

    @objc func newFromTemplate(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard let dest = targetFolder else { return }
        let cfg = ConfigStore.load()
        guard idx >= 0, idx < cfg.templates.count else { return }
        let t = cfg.templates[idx]

        let baseName = "未命名"
        let fileName = t.suffix.isEmpty ? baseName : "\(baseName).\(t.suffix)"

        withAccess(dest) {
            let target = uniqueDestination(for: fileName, in: dest)
            do {
                if let tf = t.templateFile, let tdir = SharedStore.templatesDir {
                    try FileManager.default.copyItem(at: tdir.appendingPathComponent(tf), to: target)
                } else {
                    try FileTemplate.defaultContent(forSuffix: t.suffix)
                        .write(to: target, atomically: true, encoding: .utf8)
                }
                if cfg.playSound { NSSound(named: "Pop")?.play() }
                if cfg.autoOpen { NSWorkspace.shared.open(target) }
            } catch {
                NSLog("RightPlus 新建失败: \(error)")
            }
        }
    }

    @objc func openInTerminal(_ sender: AnyObject?) {
        guard let dest = targetFolder else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        withAccess(dest) {
            NSWorkspace.shared.open([dest],
                                    withApplicationAt: terminal,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - 辅助：目标已存在时自动追加序号

    private func uniqueDestination(for name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var i = 2
        while true {
            let newName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
