//
//  rightMousePlusApp.swift
//  RightPlus
//

import SwiftUI

@main
struct rightMousePlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        Window("RightPlus", id: "main") {
            ContentView()
                .environmentObject(updater)
        }
        .defaultSize(width: 860, height: 600)
        .windowResizability(.contentMinSize)

        MenuBarExtra("RightPlus", systemImage: "cursorarrow.click.2") {
            MenuBarContent()
                .environmentObject(updater)
        }
    }
}

// MARK: - AppDelegate：Dock 显隐 + 关窗后驻留状态栏

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.applyDockPolicy(hide: UserDefaults.standard.bool(forKey: "hideDock"))
    }

    // 关闭窗口后不退出，继续驻留状态栏
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    static func applyDockPolicy(hide: Bool) {
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        if !hide { NSApp.activate(ignoringOtherApps: true) }
    }
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
    @EnvironmentObject private var updater: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 RightPlus") { showMain() }
        Button("检查更新…") { updater.check(manual: true); showMain() }
        Divider()
        Button("退出 RightPlus") { NSApplication.shared.terminate(nil) }
    }

    private func showMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
