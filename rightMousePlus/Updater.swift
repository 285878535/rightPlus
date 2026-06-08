//
//  Updater.swift
//  RightPlus —— 检查更新（国内友好：jsDelivr CDN 优先，GitHub 兜底）
//
//  优先读仓库根目录的 version.json（经 jsDelivr 国内节点），失败再依次回退到
//  其他 CDN / GitHub raw / GitHub Releases API。
//
//  version.json 格式（提交到仓库根目录，发版时更新）：
//  { "version": "1.1", "url": "下载地址", "notes": "更新说明" }
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class UpdateChecker: ObservableObject {

    static let repo = "285878535/rightPlus"
    static let branch = "main"

    /// 版本清单端点，按顺序尝试（国内可达的放前面）
    static var manifestURLs: [String] {
        [
            "https://cdn.jsdelivr.net/gh/\(repo)@\(branch)/version.json",   // jsDelivr（国内节点）
            "https://gcore.jsdelivr.net/gh/\(repo)@\(branch)/version.json", // gcore 镜像
            "https://fastly.jsdelivr.net/gh/\(repo)@\(branch)/version.json",
            "https://raw.githubusercontent.com/\(repo)/\(branch)/version.json", // GitHub raw 兜底
        ]
    }

    struct ReleaseInfo: Identifiable, Equatable {
        let version: String     // 纯版本号，如 1.1
        let downloadURL: String
        let notes: String?
        var id: String { version }
    }

    @Published var available: ReleaseInfo?
    @Published var checking = false
    @Published var upToDate = false
    @Published var errorMessage: String?

    private let skippedKey = "skippedUpdateVersion"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func check(manual: Bool = false) {
        checking = true
        upToDate = false
        errorMessage = nil
        Task { @MainActor in
            defer { checking = false }
            let (info, reachable) = await fetchInfo()
            if let info {
                if isNewer(info.version, than: currentVersion) {
                    let skipped = UserDefaults.standard.string(forKey: skippedKey)
                    if manual || skipped != info.version { available = info }
                } else if manual {
                    upToDate = true
                }
            } else if reachable {
                // 服务器可达但暂无版本信息 → 视为已是最新
                if manual { upToDate = true }
            } else if manual {
                errorMessage = "检查更新失败，请检查网络"
            }
        }
    }

    func skip(_ info: ReleaseInfo) {
        UserDefaults.standard.set(info.version, forKey: skippedKey)
        available = nil
    }

    func download(_ info: ReleaseInfo) {
        if let u = URL(string: info.downloadURL) { NSWorkspace.shared.open(u) }
        available = nil
    }

    func dismiss() { available = nil }

    // MARK: - 拉取（多端点依次尝试）

    private struct Manifest: Decodable { let version: String; let url: String; let notes: String? }
    private struct GHRelease: Decodable { let tag_name: String; let html_url: String; let body: String? }

    private enum Outcome<T> { case ok(T); case reachable; case failed }

    /// 返回 (版本信息, 是否至少有一个端点网络可达)
    private func fetchInfo() async -> (ReleaseInfo?, Bool) {
        var reachable = false
        for s in Self.manifestURLs {
            guard let url = URL(string: s) else { continue }
            let r: Outcome<Manifest> = await fetchJSON(url)
            switch r {
            case .ok(let m):
                return (ReleaseInfo(version: normalize(m.version), downloadURL: m.url, notes: m.notes), true)
            case .reachable: reachable = true
            case .failed: break
            }
        }
        if let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") {
            let r: Outcome<GHRelease> = await fetchJSON(url)
            switch r {
            case .ok(let g):
                return (ReleaseInfo(version: normalize(g.tag_name), downloadURL: g.html_url, notes: g.body), true)
            case .reachable: reachable = true
            case .failed: break
            }
        }
        return (nil, reachable)
    }

    private func fetchJSON<T: Decodable>(_ url: URL) async -> Outcome<T> {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failed }
            // 拿到 HTTP 响应即视为网络可达；仅 200 且能解析才算拿到数据
            guard http.statusCode == 200, let obj = try? JSONDecoder().decode(T.self, from: data) else {
                return .reachable
            }
            return .ok(obj)
        } catch {
            return .failed
        }
    }

    // MARK: - 版本号

    private func normalize(_ tag: String) -> String {
        (tag.hasPrefix("v") || tag.hasPrefix("V")) ? String(tag.dropFirst()) : tag
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
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

// MARK: - 更新提示弹窗

struct UpdateSheet: View {
    let release: UpdateChecker.ReleaseInfo
    let currentVersion: String
    var onDownload: () -> Void
    var onSkip: () -> Void
    var onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("发现新版本").font(.title2).bold()
                    Text("当前 \(currentVersion)　→　最新 \(release.version)")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }

            if let notes = release.notes, !notes.isEmpty {
                Text("更新内容").font(.headline)
                ScrollView {
                    Text(notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("跳过此版本", action: onSkip)
                Spacer()
                Button("稍后", action: onLater)
                Button("前往下载", action: onDownload)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
