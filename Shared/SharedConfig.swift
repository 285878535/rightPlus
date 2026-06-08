//
//  SharedConfig.swift
//  superMouse —— App 与 Finder 扩展共享的配置模型
//
//  通过 App Group 容器（group.com.xjx.rightMousePlus）共享：
//  设置 App 写入 config.json，扩展读取并生成「新建」菜单。
//

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - 单个文件模板

struct FileTemplate: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String              // 显示名称
    var suffix: String            // 后缀（不含点），可为空
    var enabled: Bool = true      // 是否在菜单中显示
    var inMainMenu: Bool = false  // 是否直接放在右键主菜单（否则在「新建」子菜单内）
    var templateFile: String?     // 容器 Templates/ 下的模板文件名；nil 则创建空文件
    var builtin: Bool = false     // 内置默认类型（只能停用，不可删除）

    enum CodingKeys: String, CodingKey {
        case id, name, suffix, enabled, inMainMenu, templateFile, builtin
    }

    init(id: UUID = UUID(), name: String, suffix: String, enabled: Bool = true,
         inMainMenu: Bool = false, templateFile: String? = nil, builtin: Bool = false) {
        self.id = id; self.name = name; self.suffix = suffix
        self.enabled = enabled; self.inMainMenu = inMainMenu
        self.templateFile = templateFile; self.builtin = builtin
    }

    // 兼容老配置：缺失字段用默认值，避免一改字段就重置用户数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        suffix = try c.decode(String.self, forKey: .suffix)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        inMainMenu = try c.decodeIfPresent(Bool.self, forKey: .inMainMenu) ?? false
        templateFile = try c.decodeIfPresent(String.self, forKey: .templateFile)
        builtin = try c.decodeIfPresent(Bool.self, forKey: .builtin) ?? false
    }

    /// 该类型对应的系统文件图标
    var icon: NSImage {
        let ws = NSWorkspace.shared
        if !suffix.isEmpty, let ut = UTType(filenameExtension: suffix) {
            return ws.icon(for: ut)
        }
        return ws.icon(for: .plainText)
    }

    /// 创建空文件时写入的初始内容（按后缀给出合理骨架）
    static func defaultContent(forSuffix suffix: String) -> String {
        switch suffix.lowercased() {
        case "html", "htm":
            return "<!DOCTYPE html>\n<html lang=\"zh\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title></title>\n</head>\n<body>\n\n</body>\n</html>\n"
        case "xml":
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        case "json":
            return "{\n}\n"
        case "sh":
            return "#!/bin/bash\n\n"
        default:
            return ""
        }
    }
}

// MARK: - 全局配置

struct SuperMouseConfig: Codable, Equatable {
    var templates: [FileTemplate]
    var showIcon: Bool = true       // 菜单显示图标
    var playSound: Bool = true      // 新建后播放提示音
    var autoOpen: Bool = false      // 新建后自动打开

    // 右键菜单项开关
    var enableCut: Bool = true
    var enableCopy: Bool = true
    var enablePaste: Bool = true
    var enableAirDrop: Bool = true
    var enableTerminal: Bool = true

    enum CodingKeys: String, CodingKey {
        case templates, showIcon, playSound, autoOpen
        case enableCut, enableCopy, enablePaste, enableAirDrop, enableTerminal
    }

    init(templates: [FileTemplate], showIcon: Bool = true, playSound: Bool = true, autoOpen: Bool = false,
         enableCut: Bool = true, enableCopy: Bool = true, enablePaste: Bool = true,
         enableAirDrop: Bool = true, enableTerminal: Bool = true) {
        self.templates = templates
        self.showIcon = showIcon; self.playSound = playSound; self.autoOpen = autoOpen
        self.enableCut = enableCut; self.enableCopy = enableCopy; self.enablePaste = enablePaste
        self.enableAirDrop = enableAirDrop; self.enableTerminal = enableTerminal
    }

    // 兼容老配置：缺失字段用默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templates = try c.decode([FileTemplate].self, forKey: .templates)
        showIcon = try c.decodeIfPresent(Bool.self, forKey: .showIcon) ?? true
        playSound = try c.decodeIfPresent(Bool.self, forKey: .playSound) ?? true
        autoOpen = try c.decodeIfPresent(Bool.self, forKey: .autoOpen) ?? false
        enableCut = try c.decodeIfPresent(Bool.self, forKey: .enableCut) ?? true
        enableCopy = try c.decodeIfPresent(Bool.self, forKey: .enableCopy) ?? true
        enablePaste = try c.decodeIfPresent(Bool.self, forKey: .enablePaste) ?? true
        enableAirDrop = try c.decodeIfPresent(Bool.self, forKey: .enableAirDrop) ?? true
        enableTerminal = try c.decodeIfPresent(Bool.self, forKey: .enableTerminal) ?? true
    }

    static let `default` = SuperMouseConfig(templates: [
        FileTemplate(name: "文本文件", suffix: "txt", builtin: true),
        FileTemplate(name: "Markdown", suffix: "md", builtin: true),
        FileTemplate(name: "RTF 富文本", suffix: "rtf", builtin: true),
        FileTemplate(name: "XML", suffix: "xml", builtin: true),
        FileTemplate(name: "HTML", suffix: "html", builtin: true),
        FileTemplate(name: "JSON", suffix: "json", builtin: true),
        FileTemplate(name: "CSV", suffix: "csv", builtin: true),
        FileTemplate(name: "Shell 脚本", suffix: "sh", builtin: true),
        FileTemplate(name: "Word 文档", suffix: "docx", templateFile: "newfile.docx", builtin: true),
        FileTemplate(name: "Excel 工作簿", suffix: "xlsx", templateFile: "newfile.xlsx", builtin: true),
        FileTemplate(name: "PPT 演示文稿", suffix: "pptx", templateFile: "newfile.pptx", builtin: true),
        FileTemplate(name: "PDF 文档", suffix: "pdf", templateFile: "newfile.pdf", builtin: true),
    ])

    /// 内置 Office 模板的后缀集合（用于旧配置迁移）
    static let builtinOfficeSuffixes = ["docx", "xlsx", "pptx", "pdf"]
    static let legacyWPSSuffixes = ["wps", "et", "dps"]
}

// MARK: - 共享存储路径
//
// 不依赖 App Group（避免付费账号/描述文件门槛）。
// 约定共享位置 = 扩展沙盒容器内的 Application Support/superMouse。
// 扩展进程：直接用自己的容器；
// 非沙盒的 App 进程：显式指向扩展容器同一目录，写入配置。

enum SharedStore {
    static let extensionBundleID = "com.xjx.rightMousePlus.FinderExtension"

    /// 共享基目录（两端解析到同一物理路径）
    static var baseDir: URL {
        let base: URL
        #if FINDER_EXTENSION
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Library/Application Support", isDirectory: true)
        #endif
        let dir = base.appendingPathComponent("superMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL? {
        baseDir.appendingPathComponent("config.json")
    }

    /// 模板文件目录（用户「添加模版文件」时拷贝到这里，扩展可读）
    static var templatesDir: URL? {
        let d = baseDir.appendingPathComponent("Templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

// MARK: - 读写

enum ConfigStore {
    static func load() -> SuperMouseConfig {
        guard let url = SharedStore.configURL,
              let data = try? Data(contentsOf: url),
              var cfg = try? JSONDecoder().decode(SuperMouseConfig.self, from: data)
        else { return .default }
        // 迁移：把与默认集同名同后缀的项标记为内置（老配置没有 builtin 字段）
        let defaultKeys = Set(SuperMouseConfig.default.templates.map { "\($0.name)|\($0.suffix)" })
        for i in cfg.templates.indices where defaultKeys.contains("\(cfg.templates[i].name)|\(cfg.templates[i].suffix)") {
            cfg.templates[i].builtin = true
        }
        // 迁移：移除旧的内置 WPS 类型，补齐新的内置 Office 类型（docx/xlsx/pptx/pdf）
        cfg.templates.removeAll {
            $0.builtin && SuperMouseConfig.legacyWPSSuffixes.contains($0.suffix.lowercased())
        }
        let existing = Set(cfg.templates.map { $0.suffix.lowercased() })
        for t in SuperMouseConfig.default.templates
        where t.builtin && SuperMouseConfig.builtinOfficeSuffixes.contains(t.suffix) && !existing.contains(t.suffix) {
            cfg.templates.append(t)
        }
        return cfg
    }

    static func save(_ cfg: SuperMouseConfig) {
        guard let url = SharedStore.configURL,
              let data = try? JSONEncoder().encode(cfg) else { return }
        try? data.write(to: url)
    }
}
