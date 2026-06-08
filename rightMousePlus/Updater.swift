//
//  Updater.swift
//  RightPlus —— 轻量更新检查
//
//  从 jsDelivr 上的 update.json 读取最新版本号，与本地版本比对；
//  发现新版只弹窗提示，点击「前往下载」跳转浏览器，用户手动下载替换。
//  不依赖签名 / 公证 / appcast，发版只需传 zip 到 GitHub 并改 update.json。
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class AppUpdater: ObservableObject {
    /// 远端版本信息地址（走 jsDelivr，国内可达）
    private let manifestURL = URL(string: "https://cdn.jsdelivr.net/gh/285878535/rightPlus@main/update.json")!

    /// 自检始终可用（保留该属性以兼容现有 UI 的 .disabled(!canCheck)）
    @Published var canCheck = true

    /// 检测到的可用新版本（nil 表示已是最新）；状态栏据此显示「发现新版」入口
    @Published var available: UpdateInfo?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    init() {
        // 启动后台静默检查：有新版才提示，已是最新不打扰
        checkInBackground()
    }

    /// 启动时静默检查
    func checkInBackground() {
        Task { await check(silent: true) }
    }

    /// 用户手动「检查更新」：无论结果都给反馈
    func checkForUpdates() {
        Task { await check(silent: false) }
    }

    private func check(silent: Bool) async {
        do {
            var req = URLRequest(url: manifestURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: req)
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)

            if Self.isNewer(info.version, than: currentVersion) {
                available = info   // 有新版：只在状态栏呈现入口，不弹窗
            } else {
                available = nil
                if !silent {
                    presentAlert(title: "已是最新版本",
                                 message: "当前版本 v\(currentVersion) 已是最新。")
                }
            }
        } catch {
            if !silent {
                presentAlert(title: "检查更新失败",
                             message: error.localizedDescription)
            }
        }
    }

    /// 打开当前可用新版的下载页面
    func openDownloadPage() {
        guard let info = available, let url = URL(string: info.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 版本比较：a 是否比 b 新（按 . 分段做数字比较，如 1.10 > 1.9）
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct UpdateInfo: Decodable {
    let version: String   // 如 "1.1"
    let url: String       // 下载页地址（GitHub release）
    let notes: String?    // 可选更新说明
}
