//
//  SettingsViews.swift
//  superMouse —— 各设置页
//

import SwiftUI
import AppKit

// MARK: - 新建文件

// 列宽常量，列头与行共用以保证对齐
private enum Col {
    static let enable: CGFloat = 40
    static let icon: CGFloat = 28
    static let tpl: CGFloat = 22
    static let suffix: CGFloat = 90
    static let main: CGFloat = 56
    static let del: CGFloat = 28
    static let hPad: CGFloat = 16
    static let spacing: CGFloat = 8
}

struct NewFileSettingsView: View {
    @State private var config = ConfigStore.load()
    @State private var showingAddType = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("新建文件").font(.title2).bold()
                Text("配置右键「新建」菜单中显示的文件类型").foregroundStyle(.secondary).font(.callout)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 12)

            columnHeader

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($config.templates) { $t in
                        let index = config.templates.firstIndex { $0.id == t.id } ?? 0
                        TemplateRow(template: $t, onDelete: {
                            config.templates.removeAll { $0.id == t.id }
                        })
                        .padding(.horizontal, Col.hPad)
                        .padding(.vertical, 7)
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035))
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 10) {
                Button { showingAddType = true } label: { Label("添加类型", systemImage: "plus") }
                Button { addTemplateFile() } label: { Label("添加模板", systemImage: "doc.badge.gearshape") }
                    .help("为某种格式指定一个空白模板文件（如 docx/wps 等需要内容结构的格式）；纯文本类型不需要")
                Spacer()
                Button(role: .destructive) { config = .default } label: { Label("重置", systemImage: "arrow.counterclockwise") }
            }
            .padding(.horizontal, Col.hPad)
            .padding(.vertical, 10)

            Divider()

            optionsFooter
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: config) { newValue in ConfigStore.save(newValue) }
        .onAppear {
            seedBuiltinTemplates()
            if let url = SharedStore.configURL, !FileManager.default.fileExists(atPath: url.path) {
                ConfigStore.save(config)
            }
        }
        .sheet(isPresented: $showingAddType) {
            AddTypeSheet { name, suffix in
                config.templates.append(FileTemplate(name: name, suffix: suffix))
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Col.spacing) {
            Text("启用").frame(width: Col.enable, alignment: .leading)
            Text("图标").frame(width: Col.icon, alignment: .leading)
            Text("显示名称").frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: Col.tpl)
            Text("后缀").frame(width: Col.suffix, alignment: .leading)
            Text("主菜单").frame(width: Col.main, alignment: .center)
            Spacer().frame(width: Col.del)
        }
        .font(.caption)
        .frame(height: 18)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Col.hPad)
        .padding(.bottom, 4)
    }

    private var optionsFooter: some View {
        HStack(spacing: 24) {
            Toggle("显示图标", isOn: $config.showIcon)
            Toggle("开启提示音", isOn: $config.playSound)
            Toggle("新建后自动打开", isOn: $config.autoOpen)
            Spacer()
        }
        .toggleStyle(.checkbox)
    }

    /// 把 App 内置的空白 Office 模板拷到共享容器（缺失才拷，幂等）
    private func seedBuiltinTemplates() {
        guard let dir = SharedStore.templatesDir else { return }
        let fm = FileManager.default
        for file in ["newfile.docx", "newfile.xlsx", "newfile.pptx", "newfile.pdf"] {
            let dest = dir.appendingPathComponent(file)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            let base = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            if let src = Bundle.main.url(forResource: base, withExtension: ext) {
                try? fm.copyItem(at: src, to: dest)
            }
        }
    }

    private func addTemplateFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "选择模板"
        guard panel.runModal() == .OK, let url = panel.url, let dir = SharedStore.templatesDir else { return }

        let fileName = url.lastPathComponent
        let dest = dir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            NSLog("RightPlus 拷贝模板失败: \(error)")
            return
        }
        config.templates.append(
            FileTemplate(name: url.deletingPathExtension().lastPathComponent,
                         suffix: url.pathExtension,
                         templateFile: fileName)
        )
    }
}

private struct TemplateRow: View {
    @Binding var template: FileTemplate
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: Col.spacing) {
            Toggle("", isOn: $template.enabled)
                .labelsHidden().toggleStyle(.checkbox)
                .frame(width: Col.enable, alignment: .leading)

            Image(nsImage: template.icon)
                .resizable().frame(width: 20, height: 20)
                .frame(width: Col.icon, alignment: .leading)

            TextField("名称", text: $template.name)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(.tint)
                .frame(width: Col.tpl)
                .opacity(template.templateFile != nil ? 1 : 0)
                .help("使用模板文件创建")

            HStack(spacing: 2) {
                Text(".").foregroundStyle(.secondary)
                TextField("后缀", text: $template.suffix)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .frame(width: Col.suffix, alignment: .leading)

            Toggle("", isOn: $template.inMainMenu)
                .labelsHidden().toggleStyle(.checkbox)
                .frame(width: Col.main, alignment: .center)
                .help("勾选后直接显示在右键主菜单，否则在「新建」子菜单内")

            if template.builtin {
                // 内置类型不可删除（只能取消勾选停用）
                Spacer().frame(width: Col.del)
            } else {
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .frame(width: Col.del)
                .help("删除此类型")
            }
        }
    }
}

// MARK: - 添加类型弹窗

private struct AddTypeSheet: View {
    var onAdd: (_ name: String, _ suffix: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加文件类型").font(.headline)

            Form {
                TextField("显示名称", text: $name, prompt: Text("如：Vue 组件"))
                TextField("后缀", text: $suffix, prompt: Text("如：vue（不含点）"))
            }
            .textFieldStyle(.roundedBorder)

            Text("将以空文件创建。若该格式需要内容结构（如 docx/wps），创建后可用「添加模板」为它指定模板文件。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    var s = suffix.trimmingCharacters(in: .whitespaces)
                    if s.hasPrefix(".") { s.removeFirst() }
                    onAdd(n.isEmpty ? "新文件" : n, s)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(suffix.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - 通用设置（扩展启用引导）

struct GeneralSettingsView: View {
    @AppStorage("hideDock") private var hideDock = false
    @State private var config = ConfigStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("通用设置").font(.title2).bold()
                Text("启用并管理 Finder 右键扩展").foregroundStyle(.secondary).font(.callout)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("右键菜单项", systemImage: "contextualmenu.and.cursorarrow").font(.headline)
                    Text("勾选要在右键菜单中显示的功能").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        Toggle("剪切", isOn: $config.enableCut)
                        Toggle("复制", isOn: $config.enableCopy)
                        Toggle("粘贴", isOn: $config.enablePaste)
                        Toggle("隔空投送", isOn: $config.enableAirDrop)
                        Toggle("在终端中打开", isOn: $config.enableTerminal)
                        Spacer()
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .onChange(of: config) { newValue in ConfigStore.save(newValue) }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("启用扩展", systemImage: "puzzlepiece.extension")
                        .font(.headline)
                    Text("1. 打开「系统设置 → 通用 → 登录项与扩展」")
                    Text("2. 在「扩展」中找到 访达扩展 / RightPlus 并勾选")
                    Text("3. 之后在访达中右键即可看到菜单；修改设置后无需重启，下次右键即生效")
                    HStack {
                        Button("打开扩展设置") { openExtensionSettings() }
                        Button("重启访达") { relaunchFinder() }
                            .help("启用后菜单未出现时可重启访达")
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("外观", systemImage: "menubar.rectangle").font(.headline)
                    Toggle("在 Dock 中隐藏（仅状态栏显示）", isOn: $hideDock)
                        .onChange(of: hideDock) { hide in
                            AppDelegate.applyDockPolicy(hide: hide)
                        }
                    Text("开启后 Dock 不显示图标，可从右上角状态栏菜单打开本窗口。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Spacer()
        }
        .padding()
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    private func relaunchFinder() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Finder"]
        try? task.run()
    }
}

// MARK: - 关于

struct AboutView: View {
    @EnvironmentObject private var appUpdater: AppUpdater

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private let features = [
        "新建文件（可自定义类型与模板）", "剪切 / 复制 / 粘贴", "在终端中打开", "隔空投送",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .padding(.top, 20)
            Text("RightPlus").font(.largeTitle).bold()
            Text("增强 macOS 右键菜单 · v\(version)").foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { f in
                    Label(f, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
            .padding(.top, 8)

            Button {
                appUpdater.checkForUpdates()
            } label: {
                Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!appUpdater.canCheck)
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - 首次启动引导

struct OnboardingSheet: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 46)).foregroundStyle(.tint)
            Text("欢迎使用 RightPlus").font(.title2).bold()
            Text("RightPlus 通过「访达扩展」增强右键菜单。首次使用需要启用扩展并授予权限：")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("打开「系统设置 → 通用 → 登录项与扩展 → 扩展」", systemImage: "1.circle.fill")
                Label("在「访达扩展」里勾选 RightPlus", systemImage: "2.circle.fill")
                Label("首次在文稿/桌面/下载等目录右键新建时，系统会弹权限请求，点「允许」即可", systemImage: "3.circle.fill")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("打开扩展设置") { openExtensionSettings() }
                Spacer()
                Button("完成") { onDone(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }
}
