//
//  Updater.swift
//  RightPlus —— 基于 Sparkle 的自动更新
//
//  检测 → 自动下载 → 校验 EdDSA 签名 → 安装并重启。
//  订阅源 SUFeedURL 指向 jsDelivr 上的 appcast.xml（国内可达）。
//

import SwiftUI
import Sparkle
import Combine

@MainActor
final class AppUpdater: ObservableObject {
    let controller: SPUStandardUpdaterController

    @Published var canCheck = false

    init() {
        // startingUpdater: true → 启动后台自动检查（首次会询问用户是否自动检查更新）
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheck)
    }

    /// 用户手动「检查更新」
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
