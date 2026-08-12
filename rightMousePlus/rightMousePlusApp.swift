//
//  rightMousePlusApp.swift
//  RightPlus
//

import SwiftUI

@main
struct rightMousePlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appUpdater = AppUpdater()

    var body: some Scene {
        Window("RightPlus", id: "main") {
            ContentView()
                .environmentObject(appUpdater)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: [])

        MenuBarExtra("RightPlus", systemImage: "cursorarrow.click.2") {
            MenuBarContent()
                .environmentObject(appUpdater)
        }
    }
}

// MARK: - AppDelegate：关窗后驻留状态栏

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 接收 rightplus:// URL —— 放在 AppDelegate 层处理，避免触发主窗口显示
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { AirDropService.handle($0) }
    }

    // 关闭窗口后不退出，继续驻留状态栏
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // URL 唤起只执行对应操作，不自动重新打开已关闭的主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
}

// MARK: - 隔空投送（由扩展通过 rightplus://airdrop 唤起）

enum AirDropService {
    static func handle(_ url: URL) {
        guard url.scheme == "rightplus", url.host == "airdrop" else { return }
        let f = SharedStore.baseDir.appendingPathComponent("airdrop.json")
        guard let data = try? Data(contentsOf: f),
              let paths = try? JSONDecoder().decode([String].self, from: data),
              !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSApp.activate(ignoringOtherApps: true)
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }
}

// MARK: - 状态栏菜单

struct MenuBarContent: View {
    @EnvironmentObject private var appUpdater: AppUpdater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 RightPlus") { showMain() }
        if let info = appUpdater.available {
            Button("发现新版本 v\(info.version) —— 前往下载") {
                appUpdater.openDownloadPage()
            }
        }
        Button("检查更新…") { appUpdater.checkForUpdates() }
            .disabled(!appUpdater.canCheck)
        Divider()
        Button("退出 RightPlus") { NSApplication.shared.terminate(nil) }
    }

    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
